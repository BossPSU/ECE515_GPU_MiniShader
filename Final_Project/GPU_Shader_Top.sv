// GPU_Shader_with_MatrixAdd.sv
import GPU_Shader_pkg::*;
import opcode_pkg::*; // assume opcodes like OP_LOAD, OP_STORE, OP_ADD, OP_MATADD

module GPU_Shader
  ( input  logic            clk,
    input  logic            rst_n,
    input  logic [31:0]     instr  [lanes-1:0],
    input  word_t           regfile [lanes-1:0][63:0],
    output word_t           write_reg_out [lanes-1:0][63:0]
  );

  // ------------------------------------------------------------
  // decode outputs (per-lane)
  // ------------------------------------------------------------
  logic [5:0]  opcode   [lanes-1:0];
  logic [4:0]  dst      [lanes-1:0];
  logic [4:0]  src0     [lanes-1:0];
  logic [4:0]  src1     [lanes-1:0];
  logic [10:0] immd     [lanes-1:0];

  decode dec (
    .instr(instr),
    .opcode(opcode),
    .dst(dst),
    .src0(src0),
    .src1(src1),
    .immd(immd)
  );

  // ------------------------------------------------------------
  // dual-ported scratchpad memory (shared)
  // ------------------------------------------------------------
  localparam int AW = $clog2(MEM_DEPTH);

  logic [AW-1:0] mem_raddr_a [lanes-1:0];
  logic [AW-1:0] mem_raddr_b [lanes-1:0];
  word_t         mem_rdata_a [lanes-1:0];
  word_t         mem_rdata_b [lanes-1:0];

  logic [lanes-1:0] mem_wen;
  logic [AW-1:0]    mem_waddr [lanes-1:0];
  word_t            mem_wdata [lanes-1:0];

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

  // ------------------------------------------------------------
  // ALUs per-lane
  // ------------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < lanes; i++) begin : lanes_block
      word_t alu_read0 = regfile[i][ src0[i] ];
      word_t alu_read1 = regfile[i][ src1[i] ];
      word_t alu_write_result;

      ALU alu_i (
        .clk          (clk),
        .read_reg0    (alu_read0),
        .read_reg1    (alu_read1),
        .mem_read_data(mem_rdata_a[i]), // optional LOAD
        .opcode       (opcode[i]),
        .immd         (immd[i]),
        .mem_write_en (mem_wen[i]),
        .mem_write_addr(mem_waddr[i]),
        .mem_write_data(mem_wdata[i]),
        .write_reg    (alu_write_result)
      );

      always_comb begin
        write_reg_out[i] = '0;
        write_reg_out[i][ dst[i] ] = alu_write_result;
      end

      // memory read addr assignment per lane
      always_comb begin
        mem_raddr_a[i] = (opcode[i] == OP_LOAD)  ? immd[i][AW-1:0] : '0;
        mem_raddr_b[i] = (opcode[i] == OP_STORE) ? immd[i][AW-1:0] : '0;
      end
    end
  endgenerate

  // ------------------------------------------------------------
  // ----------------- MATRIX ADD ENGINE ------------------------
  // ------------------------------------------------------------
  logic            mat_start;
  logic [31:0]     mat_baseA, mat_baseB, mat_baseC;
  logic [31:0]     mat_length;
  logic            mat_busy, mat_done;

  // memory interface for engine
  logic [AW-1:0] mat_raddrA [lanes-1:0];
  logic [AW-1:0] mat_raddrB [lanes-1:0];
  word_t         mat_rdataA [lanes-1:0];
  word_t         mat_rdataB [lanes-1:0];
  logic [lanes-1:0] mat_wen;
  logic [AW-1:0] mat_waddr [lanes-1:0];
  word_t         mat_wdata [lanes-1:0];

  MatrixAddEngine #(
    .lanes(lanes),
    .MEM_DEPTH(MEM_DEPTH)
  ) mat_eng (
    .clk(clk),
    .rst_n(rst_n),
    .start(mat_start),
    .baseA(mat_baseA),
    .baseB(mat_baseB),
    .baseC(mat_baseC),
    .length(mat_length),
    .busy(mat_busy),
    .done(mat_done),
    .mem_raddrA_in(mat_raddrA),
    .mem_raddrB_in(mat_raddrB),
    .mem_rdataA_out(mat_rdataA),
    .mem_rdataB_out(mat_rdataB),
    .memC_wen_out(mat_wen),
    .memC_waddr_out(mat_waddr),
    .memC_wdata_out(mat_wdata)
  );

  // ------------------------------------------------------------
  // GPU FSM (minimal for MatrixAdd)
  // ------------------------------------------------------------
  typedef enum logic [1:0] {IDLE=2'd0, RUN=2'd1, WAIT_ENGINE=2'd2} state_t;
  state_t state = IDLE;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      mat_start <= 0;
    end else begin
      case(state)
        IDLE: begin
          if (opcode[0] == OP_MATADD) begin
            // Example: take register values as baseA/B/C/length
            mat_baseA <= regfile[0][ src0[0] ];
            mat_baseB <= regfile[0][ src1[0] ];
            mat_baseC <= regfile[0][ dst[0] ];
            mat_length <= regfile[0][ immd[0] ]; // immediate can hold length
            mat_start <= 1'b1;
            state <= WAIT_ENGINE;
          end else begin
            mat_start <= 0;
          end
        end
        WAIT_ENGINE: begin
          mat_start <= 0; // one-cycle pulse
          if (mat_done) state <= IDLE;
        end
      endcase
    end
  end

  // ------------------------------------------------------------
  // ------------------- MEMORY CONNECTION ---------------------
  // ------------------------------------------------------------
  // Combine normal ALU memory writes with MatrixAdd memory writes
  always_comb begin
    for (int j = 0; j < lanes; j++) begin
      // If MatrixAddEngine is active, its writes override ALU writes
      mem_wen[j]   = mat_busy ? mat_wen[j]   : mem_wen[j];
      mem_waddr[j] = mat_busy ? mat_waddr[j] : mem_waddr[j];
      mem_wdata[j] = mat_busy ? mat_wdata[j] : mem_wdata[j];

      // read addresses: ALU or engine
      mem_raddr_a[j] = mat_busy ? mat_raddrA[j] : mem_raddr_a[j];
      mem_raddr_b[j] = mat_busy ? mat_raddrB[j] : mem_raddr_b[j];
    end
  end

endmodule
