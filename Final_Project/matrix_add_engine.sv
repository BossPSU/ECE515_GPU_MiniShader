import GPU_Shader_pkg::*;

module MatrixAddEngine
  ( input  logic            clk,
    input  logic            rst_n,          // active-low reset
    input  logic            start,          // pulse to start the operation
    input  logic [31:0]     baseA,          // byte/word addresses? here we assume word addresses (0..MEM_DEPTH-1)
    input  logic [31:0]     baseB,
    input  logic [31:0]     baseC,
    input  int unsigned     length,         // number of elements to add
    output logic            busy,
    output logic            done
  );

  // width for addressing mem: use log2 of MEM_DEPTH
  localparam int AW = $clog2(MEM_DEPTH);

  // local copies/converted bases
  logic [AW-1:0] baseA_a, baseB_a, baseC_a;
  always_comb begin
    baseA_a = baseA[AW-1:0];
    baseB_a = baseB[AW-1:0];
    baseC_a = baseC[AW-1:0];
  end

  // memory interface signals (per-lane)
  logic                 mem_wen   [lanes-1:0];
  logic [AW-1:0]       mem_waddr [lanes-1:0];
  word_t                mem_wdata [lanes-1:0];
  logic [AW-1:0]       mem_raddrA[lanes-1:0];
  logic [AW-1:0]       mem_raddrB[lanes-1:0];
  word_t                mem_rdataA[lanes-1:0];
  word_t                mem_rdataB[lanes-1:0];

  // For memory we will instantiate one mem_scratchpad and use two logical read ports by wiring,
  // but our mem_scratchpad currently supports only one read_addr per lane. To read both A and B
  // addresses simultaneously we will treat that each lane reads one address from "read_addr" array.
  // So we need two mem instances or we pack: easiest is to instantiate two scratchpads (A-bank and B-bank),
  // or we can implement a single scratchpad and perform two cycles per chunk. For simplicity and highest parallelism,
  // instantiate two separate scratchpads here: memA and memB (both initialised identically in testbench).
  // (This mirrors having both matrices resident or using dual-ported memory.)

  // Instantiate two scratchpads: memA (holds A) and memB (holds B), and memC for output.
  // For simplicity of this example, we instantiate 3 banks. In practice you might use multi-port memory or banks.

  // read addresses & write ports for memA, memB, memC:
  logic [AW-1:0] memA_raddr [lanes-1:0];
  logic [AW-1:0] memB_raddr [lanes-1:0];
  word_t         memA_rdata [lanes-1:0];
  word_t         memB_rdata [lanes-1:0];
  logic [lanes-1:0] memA_wen; // not used for this example (we presuppose A and B were pre-loaded)
  logic [lanes-1:0] memB_wen;

  // memC write ports
  logic [lanes-1:0] memC_wen;
  logic [AW-1:0]    memC_waddr [lanes-1:0];
  word_t            memC_wdata [lanes-1:0];
  logic [lanes-1:0] memC_r_en_unused;
  logic [AW-1:0] memC_raddr_unused [lanes-1:0];
  word_t memC_rdata_unused [lanes-1:0];

  // instantiate mem banks
  mem_scratchpad #(.ADDR_WIDTH(AW)) memA (
    .clk(clk),
    .write_en(memA_wen),
    .write_addr('{default: '0}),
    .write_data('{default: '0}),
    .read_addr(memA_raddr),
    .read_data(memA_rdata)
  );

  mem_scratchpad #(.ADDR_WIDTH(AW)) memB (
    .clk(clk),
    .write_en(memB_wen),
    .write_addr('{default: '0}),
    .write_data('{default: '0}),
    .read_addr(memB_raddr),
    .read_data(memB_rdata)
  );

  // memC (output)
  mem_scratchpad #(.ADDR_WIDTH(AW)) memC (
    .clk(clk),
    .write_en(memC_wen),
    .write_addr(memC_waddr),
    .write_data(memC_wdata),
    .read_addr(memC_raddr_unused),
    .read_data(memC_rdata_unused)
  );

  // Per-lane ALUs (compute sum)
  genvar gi;
  generate
    for (gi = 0; gi < lanes; gi++) begin : ALUS
      ALU_ADD alu_i (
        .a(memA_rdata[gi]),
        .b(memB_rdata[gi]),
        .sum(memC_wdata[gi])
      );
    end
  endgenerate

  // Control FSM and index pointer
  typedef enum logic [1:0] {IDLE=2'd0, RUN=2'd1, DONE=2'd2} state_t;
  state_t state;
  int unsigned idx; // element index (0..length-1)

  // internal valid mask per lane
  logic valid_lane [lanes-1:0];

  // FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      idx   <= 0;
      busy  <= 1'b0;
      done  <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          done <= 1'b0;
          busy <= 1'b0;
          if (start) begin
            idx <= 0;
            busy <= 1'b1;
            state <= RUN;
          end
        end

        RUN: begin
          // issue a chunk of up to 'lanes' elements this cycle.
          // mem reads are combinational -> ALUs produce sum this cycle.
          // memC writes will commit on next rising edge inside memC instance.

          // after issuing, advance idx
          if (idx + lanes >= length) begin
            // last chunk (may be partial)
            idx <= idx + lanes; // moves beyond length; we'll detect completion next cycle
            state <= DONE;
          end else begin
            idx <= idx + lanes;
          end
        end

        DONE: begin
          busy <= 1'b0;
          done <= 1'b1;
          // remain DONE until start deasserted and asserted again
          if (!start) begin
            state <= IDLE;
            done <= 1'b0;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  // compute per-lane read/write addresses every cycle based on current idx
  // Note: we compute addresses based on the idx value *observed in this cycle*.
  // To make the addresses correspond to the chunk we just issued, derive a base index variable 'issue_base'
  // that equals the idx value at the start of the RUN cycle. Simpler: compute base = (state==IDLE && start) ? 0 : (state==RUN ? idx : idx);
  // For clarity, use a combinational view: we want the addresses that correspond to the chunk beginning at "issue_ptr".
  // We'll make an 'issue_ptr' that latches idx at the cycle we transition into RUN or at each RUN cycle start.
  logic [31:0] issue_ptr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) issue_ptr <= '0;
    else begin
      if (state == IDLE && start) begin
        issue_ptr <= 0;
      end else if (state == RUN) begin
        // issue_ptr holds the index of the chunk we are currently issuing (previous idx value)
        issue_ptr <= idx;
      end
    end
  end

  // Form addresses and valid lanes
  always_comb begin
    // default values
    for (int i = 0; i < lanes; i++) begin
      int unsigned elem_idx = issue_ptr + i;
      valid_lane[i] = (elem_idx < length);
      memA_raddr[i] = (baseA_a + elem_idx)[AW-1:0];
      memB_raddr[i] = (baseB_a + elem_idx)[AW-1:0];
      // prepare memC write addr
      memC_waddr[i] = (baseC_a + elem_idx)[AW-1:0];
      // memC write enable only if lane is valid and we're in RUN (issue)
      memC_wen[i] = (state == RUN) && valid_lane[i];
    end

    // memA and memB write enables are 0 for this example (we assume they are preloaded)
    for (int i = 0; i < lanes; i++) begin
      memA_wen[i] = 1'b0;
      memB_wen[i] = 1'b0;
    end
  end

endmodule
