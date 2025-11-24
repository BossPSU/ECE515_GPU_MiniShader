`timescale 1ns/1ps
import GPU_Shader_pkg::*;
import opcode_pkg::*;
module GPU_Top
  ( input logic clk,
    input logic rst_n,
    // simple instruction memory input: broadcasted instruction (per fetch)
    input logic [31:0] instr_mem [0:255], // small instr memory; you can load this in TB
    input int unsigned instr_count
  );

  // ---------- helpers ----------
  // convert active-low rst_n to active-high reset for MatrixMulEngine (it expects rst)
  logic reset_h = ~rst_n;

  // ---------- Program counter + pipeline stage registers ----------
  int unsigned pc;
  logic [31:0] fetched_instr;       // broadcast
  logic [5:0]  decoded_opcode;
  logic [4:0]  decoded_dst, decoded_src0, decoded_src1;
  logic [10:0] decoded_immd;

  // simple regfile: lanes x NUM_REGS, synchronous write
  word_t regfile [lanes-1:0][NUM_REGS-1:0];
  // regfile writeback control per-lane
  logic regfile_we [lanes-1:0];
  logic [$clog2(NUM_REGS)-1:0] regfile_waddr [lanes-1:0];
  word_t regfile_wdata [lanes-1:0];

  // ---------- Shared memory instance ----------
  localparam int AW = $clog2(MEM_DEPTH);
  logic [AW-1:0] mem_raddr_a [lanes-1:0];
  logic [AW-1:0] mem_raddr_b [lanes-1:0];
  word_t         mem_rdata_a [lanes-1:0];
  word_t         mem_rdata_b [lanes-1:0];
  logic [lanes-1:0] mem_wen;
  logic [AW-1:0]    mem_waddr [lanes-1:0];
  word_t            mem_wdata [lanes-1:0];

  // instantiate dual-port memory (assumed to accept array-style ports)
  mem_dualport #(.ADDR_WIDTH(AW)) mem0 (
    .clk(clk),
    .write_en(mem_wen),
    .write_addr(mem_waddr),
    .write_data(mem_wdata),
    .read_addr_a(mem_raddr_a),
    .read_data_a(mem_rdata_a),
    .read_addr_b(mem_raddr_b),
    .read_data_b(mem_rdata_b)
  );

  // initialize memory access defaults
  initial begin
    for (int l = 0; l < lanes; l++) begin
      mem_raddr_a[l] = '0;
      mem_raddr_b[l] = '0;
      mem_wen[l]     = 1'b0;
      mem_waddr[l]   = '0;
      mem_wdata[l]   = '0;
    end
  end

  // ---------- Per-lane ALUs (scalar ops) ----------
  // We will instantiate ALUs per lane and wire memory read ports for normal ops (ALU uses read port A for LOAD)
  logic [5:0] opcode_per_lane [lanes-1:0];
  logic [4:0] dst_per_lane [lanes-1:0];
  logic [4:0] src0_per_lane [lanes-1:0];
  logic [4:0] src1_per_lane [lanes-1:0];
  logic [10:0] immd_per_lane [lanes-1:0];

  // broadcasting fetched instruction to lanes
  always_comb begin
    for (int l=0; l<lanes; l++) begin
      opcode_per_lane[l] = decoded_opcode;
      dst_per_lane[l]    = decoded_dst;
      src0_per_lane[l]   = decoded_src0;
      src1_per_lane[l]   = decoded_src1;
      immd_per_lane[l]   = decoded_immd;
    end
  end

  // ALU outputs
  logic regwb_en_per_lane [lanes-1:0];
  word_t regwb_data_per_lane [lanes-1:0];
  logic memreq_wen_per_lane [lanes-1:0];
  logic [AW-1:0] memreq_waddr_per_lane [lanes-1:0];
  word_t memreq_wdata_per_lane [lanes-1:0];

  // instantiate ALUs
  generate
    for (genvar l = 0; l < lanes; l++) begin : ALUS_GEN
      ALU alu_inst (
        .read_reg0     (regfile[l][ src0_per_lane[l] ]),
        .read_reg1     (regfile[l][ src1_per_lane[l] ]),
        .mem_read_data (mem_rdata_a[l]),
        .opcode        (opcode_per_lane[l]),
        .immd          (immd_per_lane[l]),
        .reg_write_en  (regwb_en_per_lane[l]),
        .reg_write_idx (), // top owns idx by using dst_per_lane
        .reg_write_data(regwb_data_per_lane[l]),
        .mem_write_en  (memreq_wen_per_lane[l]),
        .mem_write_addr(memreq_waddr_per_lane[l]),
        .mem_write_data(memreq_wdata_per_lane[l])
      );
    end
  endgenerate

  // ---------- Accelerators: MatrixAdd & MatrixMul instances ----------
  logic matadd_start, matmul_start;
  logic [31:0] mat_baseA, mat_baseB, mat_baseC;
  logic [31:0] mat_length; // for matadd
  logic matadd_busy, matadd_done, matmul_busy, matmul_done;

  // engine memory ports (connect to the shared mem ports)
  logic [AW-1:0] eng_raddrA [lanes-1:0], eng_raddrB [lanes-1:0];
  word_t         eng_rdataA [lanes-1:0], eng_rdataB [lanes-1:0];
  logic [lanes-1:0] eng_wen;
  logic [AW-1:0]    eng_waddr [lanes-1:0];
  word_t            eng_wdata [lanes-1:0];

  // connect engine read-data outputs to memory read-data (these are already wired below by assignment)
  // (eng_rdata* will be driven from mem_rdata* later by always_comb assignments)

  // ---------- MatrixAddEngine (fixed port names) ----------
  MatrixAddEngine #(.LANES(lanes)) matadd (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (matadd_start),
    .baseA      (mat_baseA),
    .baseB      (mat_baseB),
    .baseC      (mat_baseC),
    .length     (mat_length),
    .busy       (matadd_busy),
    .done       (matadd_done),

    // memory ports (names must match the module)
    .mem_raddrA (eng_raddrA),
    .mem_raddrB (eng_raddrB),
    .mem_rdataA (eng_rdataA),
    .mem_rdataB (eng_rdataB),
    .mem_wen    (eng_wen),
    .mem_waddr  (eng_waddr),
    .mem_wdata  (eng_wdata)
  );

  // ---------- MatrixMulEngine integration (uses 2D arrays inside) ----------
  // We'll integrate your provided MatrixMulEngine (it expects full A/B arrays).
  // Create local 2D arrays to hold a small NxN matrix; adapt MAT_N as needed.
  localparam int MAT_N = 4; // must match or be <= MatrixMulEngine parameter N
  localparam int MAT_DATA_W = $bits(word_t); // assume word_t is the same width used by MatrixMulEngine

  // local 2D matrices
  logic [MAT_DATA_W-1:0] A_mat [0:MAT_N-1][0:MAT_N-1];
  logic [MAT_DATA_W-1:0] B_mat [0:MAT_N-1][0:MAT_N-1];
  logic [MAT_DATA_W-1:0] C_mat [0:MAT_N-1][0:MAT_N-1];

  // Instantiate the MatrixMulEngine (the module you provided) and connect local arrays
  MatrixMulEngine #(
    .N(MAT_N),
    .DATA_W(MAT_DATA_W),
    .LANES(lanes)         // use the same lanes parameter so both agree on parallelism
  ) matmul_inst (
    .clk   (clk),
    .rst   (reset_h),      // convert from rst_n active-low to active-high reset
    .start (matmul_start),

    .A     (A_mat),
    .B     (B_mat),
    .C     (C_mat),

    .done  (matmul_done)
  );

  // ---------- MatrixMul wrapper FSM: load A,B from mem0 into A_mat/B_mat, start matmul, then write C back ----------
  typedef enum logic [2:0] {MM_IDLE=3'd0, MM_LOAD=3'd1, MM_START=3'd2, MM_WAIT=3'd3, MM_WRITEBACK=3'd4, MM_DONE=3'd5} mm_state_t;
  mm_state_t mm_state, mm_next;

  // linear index used for load/writeback (0 .. MAT_N*MAT_N-1)
  int unsigned mm_idx;
  int unsigned mm_next_idx;

  // single-lane usage for loader/writer: use lane 0 of mem_raddr_a/mem_rdata_a to stream data
  // We'll use eng_raddrA[0] / eng_rdataA[0] as engine-visible ports too; while matadd/matmul busy,
  // engines will override top mem ports; so here we assert matmul_busy while we are doing this sequence
  // (we will instead use mm_busy internal flag to coordinate; but set matmul_busy while the operation is active)
  logic mm_requested; // indicates we are in an mm operation (affects arbitration)
  // local temporary to capture mem read data (sampled next cycle)
  word_t tmp_read_data;

  // compute TOT entries
  localparam int MM_TOT = MAT_N * MAT_N;

  // combinational next-index computation (increment by 1)
  always_comb begin
    mm_next_idx = mm_idx + 1;
  end

  // mm_state sequential
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mm_state <= MM_IDLE;
      mm_idx <= 0;
      mm_requested <= 1'b0;
      matmul_busy <= 1'b0;
      matmul_start <= 1'b0;
    end else begin
      mm_state <= mm_next;
      mm_idx <= mm_next_idx;
      // small control: start pulse should be one-cycle
      if (mm_state == MM_START) matmul_start <= 1'b1;
      else matmul_start <= 1'b0;

      // maintain busy flag while we're in the sequence or engine is busy
      if (mm_state != MM_IDLE && mm_state != MM_DONE) matmul_busy <= 1'b1;
      else matmul_busy <= 1'b0;
    end
  end

  // mm_state next logic and operations
  always_comb begin
    // defaults
    mm_next = mm_state;
    // default: no special memory addresses driven by loader unless in LOAD/WRITEBACK
    // ENGINE ports eng_raddrA/eng_raddrB / eng_wen etc will be driven by the loader/writer below when active
    case (mm_state)
      MM_IDLE: begin
        if (matmul_start) begin
          // reset index (note: assume mat_baseA/B/C already set)
          mm_next = MM_LOAD;
        end
      end
      MM_LOAD: begin
        // iterate through all elements to load A and B sequentially using lane-0 read port
        if (mm_idx >= MM_TOT) begin
          mm_next = MM_START; // all loaded
        end else begin
          mm_next = MM_LOAD;
        end
      end
      MM_START: begin
        // start the combinational engine (pulse will be generated in sequential block)
        mm_next = MM_WAIT;
      end
      MM_WAIT: begin
        // wait for matrix engine to indicate done
        if (matmul_done) mm_next = MM_WRITEBACK;
      end
      MM_WRITEBACK: begin
        // write back C entries sequentially
        if (mm_idx >= MM_TOT) mm_next = MM_DONE;
        else mm_next = MM_WRITEBACK;
      end
      MM_DONE: begin
        mm_next = MM_IDLE; // return to idle; top logic may clear matmul_start externally
      end
      default: mm_next = MM_IDLE;
    endcase
  end

  // Provide behaviour for LOAD and WRITEBACK phases (drive eng_* ports to interact with mem_dualport)
  // We'll use lane 0 only as the sequencer I/O for simplicity; make sure other lanes are idle during these phases.
  // NOTE: eng_raddrA/B and eng_w* are connected to memory arbitration below when matmul_busy asserted.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // clear A_mat/B_mat
      for (int r=0; r<MAT_N; r++) for (int c=0; c<MAT_N; c++) begin
        A_mat[r][c] <= '0;
        B_mat[r][c] <= '0;
        C_mat[r][c] <= '0;
      end
      mm_idx <= 0;
      tmp_read_data <= '0;
    end else begin
      if (mm_state == MM_LOAD) begin
        // Drive memory read addresses to fetch A and B elements sequentially.
        // We'll place the read address on mem_raddr_a[0], and on the next cycle capture mem_rdata_a[0].
        // Compute element row/col from mm_idx and capture into A_mat and B_mat on the following cycle.
        // Set eng_raddrA[0] / eng_raddrB[0] to point to baseA + idx and baseB + idx.
        // We need to sample the read data after one clock — model assumes mem_rdata_a returns valid next cycle.
        // During load phase we keep other eng_* signals zero.
        // (Write addresses are not used in load phase.)
        // Note: mm_idx increments in sequential block; we use mm_idx as current address index.
        // Set addresses (these are observed by memory combinationally)
        // (the actual sampling of returned data into A_mat/B_mat is done below by reading mem_rdata_a[0])
      end else if (mm_state == MM_START) begin
        // nothing to do here — start pulse is generated in the sequential block
      end else if (mm_state == MM_WAIT) begin
        // waiting for matmul engine to finish; do not drive memory addresses for ALUs
      end else if (mm_state == MM_WRITEBACK) begin
        // similar sequential writer: place C element on eng_wdata[0] and assert eng_wen[0], set eng_waddr[0] accordingly.
      end
      // The actual sample/store of mem_rdata_a for LOAD and issuing writes for WRITEBACK happen below
    end
  end

  // For synthesizable clarity and to keep this module simple, implement the actual micro-ops
  // (address driving and sampling) in a separate always_ff to maintain timing (one-cycle read latency).
  // We'll use a simple micro-step counter to control read/sample vs increment.
  typedef enum logic [1:0] {PH_IDLE=2'd0, PH_ISSUE=2'd1, PH_SAMPLE=2'd2} ph_t;
  ph_t phase, next_phase;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) phase <= PH_IDLE;
    else phase <= next_phase;
  end

  always_comb begin
    next_phase = phase;
    if (mm_state == MM_LOAD) begin
      case (phase)
        PH_IDLE: next_phase = PH_ISSUE;
        PH_ISSUE: next_phase = PH_SAMPLE;
        PH_SAMPLE: next_phase = PH_ISSUE;
        default: next_phase = PH_IDLE;
      endcase
    end else if (mm_state == MM_WRITEBACK) begin
      case (phase)
        PH_IDLE: next_phase = PH_ISSUE;
        PH_ISSUE: next_phase = PH_SAMPLE;
        PH_SAMPLE: next_phase = PH_ISSUE;
        default: next_phase = PH_IDLE;
      endcase
    end else begin
      next_phase = PH_IDLE;
    end
  end

  // Now implement the phase operations (issue addresses / sample data / issue writes)
  // We'll use mm_idx as the current element pointer (0..MM_TOT-1). On PH_ISSUE place addresses or write data,
  // on PH_SAMPLE capture read data and increment mm_idx. During WRITEBACK, PH_ISSUE will assert eng_wen[0].
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mm_idx <= 0;
      // clear all engine ports used by loader/writer
      for (int l=0; l<lanes; l++) begin
        eng_raddrA[l] <= '0;
        eng_raddrB[l] <= '0;
        eng_wen[l]    <= 1'b0;
        eng_waddr[l]  <= '0;
        eng_wdata[l]  <= '0;
      end
    end else begin
      // defaults each cycle
      for (int l=0; l<lanes; l++) begin
        eng_raddrA[l] <= eng_raddrA[l]; // retain by default
        eng_raddrB[l] <= eng_raddrB[l];
        eng_wen[l]    <= 1'b0;
        eng_waddr[l]  <= eng_waddr[l];
        eng_wdata[l]  <= eng_wdata[l];
      end

      if (mm_state == MM_LOAD) begin
        if (phase == PH_ISSUE) begin
          if (mm_idx < MM_TOT) begin
            // compute element addresses
            automatic int unsigned row;
            automatic int unsigned col;
            row = mm_idx / MAT_N;
            col = mm_idx % MAT_N;
            // place addresses onto eng read ports (use lane 0)
            eng_raddrA[0] <= mat_baseA[$clog2(MEM_DEPTH)-1:0] + mm_idx;
            eng_raddrB[0] <= mat_baseB[$clog2(MEM_DEPTH)-1:0] + mm_idx;
          end
        end else if (phase == PH_SAMPLE) begin
          if (mm_idx < MM_TOT) begin
            // sample mem data returned on eng_rdataA[0]/eng_rdataB[0] (connected to mem_rdata_a[0] by arbitration)
            automatic int unsigned row;
            automatic int unsigned col;
            row = mm_idx / MAT_N;
            col = mm_idx % MAT_N;
            A_mat[row][col] <= eng_rdataA[0];
            B_mat[row][col] <= eng_rdataB[0];
            mm_idx <= mm_idx + 1;
          end
        end
      end else if (mm_state == MM_WRITEBACK) begin
        if (phase == PH_ISSUE) begin
          if (mm_idx < MM_TOT) begin
            automatic int unsigned row;
            automatic int unsigned col;
            row = mm_idx / MAT_N;
            col = mm_idx % MAT_N;
            eng_waddr[0] <= mat_baseC[$clog2(MEM_DEPTH)-1:0] + mm_idx;
            eng_wdata[0] <= C_mat[row][col];
            eng_wen[0]   <= 1'b1;
          end
        end else if (phase == PH_SAMPLE) begin
          if (mm_idx < MM_TOT) begin
            mm_idx <= mm_idx + 1;
          end
        end
      end else begin
        // keep default values
      end
    end
  end

  // ---------- Arbitration: when engine busy, override memory ports ----------
  // Combine eng_* into mem_* when matadd_busy or matmul_busy (or loader/writer phases)
  always_comb begin
    // default: ALU-driven requests
    for (int l=0; l<lanes; l++) begin
      // ALU mem outputs were assigned in T_DISPATCH (sequential). However always_comb must provide default values here.
      mem_raddr_a[l] = mem_raddr_a[l]; // keep default (driven elsewhere in T_DISPATCH)
      mem_raddr_b[l] = mem_raddr_b[l];
      mem_wen[l]     = memreq_wen_per_lane[l];
      mem_waddr[l]   = memreq_waddr_per_lane[l];
      mem_wdata[l]   = memreq_wdata_per_lane[l];
    end

    // If MatrixAdd engine is busy, it takes priority over ALUs
    if (matadd_busy) begin
      for (int l=0; l<lanes; l++) begin
        mem_raddr_a[l] = eng_raddrA[l];
        mem_raddr_b[l] = eng_raddrB[l];
        mem_wen[l]     = eng_wen[l];
        mem_waddr[l]   = eng_waddr[l];
        mem_wdata[l]   = eng_wdata[l];
      end
    end

    // If MatrixMul operation (either loader/engine/writeback) is active, give it priority as well
    if (mm_state != MM_IDLE) begin
      // During mm operation we only use lane 0 as the streaming port; make sure other lanes are not driving memory
      for (int l=0; l<lanes; l++) begin
        if (l == 0) begin
          mem_raddr_a[0] = eng_raddrA[0];
          mem_raddr_b[0] = eng_raddrB[0];
          mem_wen[0]     = eng_wen[0];
          mem_waddr[0]   = eng_waddr[0];
          mem_wdata[0]   = eng_wdata[0];
        end else begin
          // other lanes tri-stated / set to zero during mm operation
          mem_raddr_a[l] = '0;
          mem_raddr_b[l] = '0;
          mem_wen[l]     = 1'b0;
          mem_waddr[l]   = '0;
          mem_wdata[l]   = '0;
        end
      end
    end
  end

  // ---------- connect memory read outputs to engine and ALU ----------
  always_comb begin
    for (int l=0; l<lanes; l++) begin
      eng_rdataA[l] = mem_rdata_a[l];
      eng_rdataB[l] = mem_rdata_b[l];
    end
  end

  // ---------- Simple top FSM: Fetch/Decode/Dispatch/Writeback ----------
  typedef enum logic [1:0] {T_IDLE=2'd0, T_FETCH=2'd1, T_DISPATCH=2'd2} top_state_t;
  top_state_t tstate;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tstate <= T_IDLE; pc <= 0;
      matadd_start <= 0; // matmul_start is controlled by the mm FSM
      matmul_start <= 0;
      // clear regfile (optional)
      for (int r=0;r<NUM_REGS;r++) for (int l=0;l<lanes;l++) regfile[l][r] <= '0;
    end else begin
      case (tstate)
        T_IDLE: begin
          // start fetching instruction stream
          tstate <= T_FETCH;
        end
        T_FETCH: begin
          if (pc < instr_count) begin
            fetched_instr <= instr_mem[pc];
            tstate <= T_DISPATCH;
          end
        end
        T_DISPATCH: begin
          // decode fields from fetched_instr (same encoding as before)
          decoded_opcode <= fetched_instr[31:26];
          decoded_dst    <= fetched_instr[25:21];
          decoded_src0   <= fetched_instr[20:16];
          decoded_src1   <= fetched_instr[15:11];
          decoded_immd   <= fetched_instr[10:0];

          // check for accelerator opcodes (by convention we use lane-0's decode)
          if (decoded_opcode == OP_MATADD) begin
            // Use registers to hold base/length or encode immediate as length
            mat_baseA  <= regfile[0][decoded_src0];
            mat_baseB  <= regfile[0][decoded_src1];
            mat_baseC  <= regfile[0][decoded_dst];
            mat_length <= regfile[0][decoded_immd]; // optional
            matadd_start <= 1'b1;
          end else if (decoded_opcode == OP_MATMUL) begin
            // populate mat_baseA/B/C from registers; start is handled by mm driver
            mat_baseA <= regfile[0][decoded_src0];
            mat_baseB <= regfile[0][decoded_src1];
            mat_baseC <= regfile[0][decoded_dst];
            // assert top-level request to mm FSM by toggling a handshake flag
            matmul_start <= 1'b1; // mm FSM will detect this and move to load state
          end else begin
            // For scalar ops, process per-lane ALU outputs and writeback into regfile
            // commit ALU reg writebacks synchronously
            for (int l=0; l<lanes; l++) begin
              if (regwb_en_per_lane[l]) begin
                regfile[l][ dst_per_lane[l] ] <= regwb_data_per_lane[l];
              end
              // memory writes from ALUs requested:
              // (these will be used by arbitration unless an engine takes priority)
              memreq_wen_per_lane[l] = memreq_wen_per_lane[l];
              memreq_waddr_per_lane[l] = memreq_waddr_per_lane[l];
              memreq_wdata_per_lane[l] = memreq_wdata_per_lane[l];

              // mem read addresses for ALUs:
              // NOTE: assign here to mem_raddr_a (will be overridden when engines active)
              mem_raddr_a[l] <= (opcode_per_lane[l] == OP_LOAD) ? immd_per_lane[l][AW-1:0] : '0;
              mem_raddr_b[l] <= '0;
            end
          end

          // clear starts after dispatch cycle (matmul_start pulse is one cycle)
          if (matadd_start) matadd_start <= 1'b0;
          // matmul_start is cleared by mm FSM / sequential block (we intentionally let it be single-cycle)

          // advance program counter (simple)
          pc <= pc + 1;
          tstate <= T_FETCH;
        end
      endcase
    end
  end

endmodule
