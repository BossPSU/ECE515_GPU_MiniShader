// GPU_Top_matadd.sv
`timescale 1ns/1ps

import GPU_Shader_pkg::*; // lanes, MEM_DEPTH, NUM_REGS, word_t
import opcode_pkg::*;     // canonical opcodes from opcode_pkg

module GPU_Top
  #(
    parameter int LANES = lanes,
    parameter int IMEM_DEPTH = 64
  )
  (
    input  logic clk,
    input  logic rst_n,
    input  logic start   // pulse: start program (loads PC=0)
  );

  // Instruction format (canonical from opcode_pkg)
  typedef logic [31:0] instr_word_t;
  typedef struct packed {
    opcodes_t opcode;
    logic [5:0] dst;
    logic [5:0] src0;
    logic [5:0] src1;
    logic [7:0] imm8;
  } instr_t;

  // Program memory + PC
  instr_word_t imem [0:IMEM_DEPTH-1];
  int unsigned pc;

  // Fetch/execute latch
  instr_t fetched_instr;
  logic fetched_valid;

  // per-lane register file
  word_t regfile [LANES-1:0][NUM_REGS-1:0];

  // read operands (combinational)
  word_t read_reg0 [LANES-1:0];
  word_t read_reg1 [LANES-1:0];

  // decoded/broadcast fields for current instruction under execution
  opcodes_t cur_opcode;
  logic [5:0] cur_dst;
  logic [5:0] cur_src0;
  logic [5:0] cur_src1;
  logic [10:0] cur_immd; // zero-extended imm8

  // per-lane ALU outputs (combinational)
  logic        alu_reg_write_en [LANES-1:0];
  word_t       alu_reg_write_data[LANES-1:0];

  logic        alu_mem_write_en [LANES-1:0];
  logic [$clog2(MEM_DEPTH)-1:0] alu_mem_write_addr [LANES-1:0];
  word_t       alu_mem_write_data [LANES-1:0];

  // memory ports (connected to scratchpad mem_dualport)
  logic [$clog2(MEM_DEPTH)-1:0] mem_raddrA [LANES-1:0];
  logic [$clog2(MEM_DEPTH)-1:0] mem_raddrB [LANES-1:0];
  wire  word_t                  mem_rdataA [LANES-1:0];
  wire  word_t                  mem_rdataB [LANES-1:0];
  logic [LANES-1:0]             mem_wen;
  logic [$clog2(MEM_DEPTH)-1:0] mem_waddr [LANES-1:0];
  word_t                        mem_wdata [LANES-1:0];

  // ---------------------------
  // Accelerator signals (MatrixAddEngine)
  // ---------------------------
  logic        eng_start;
  logic        eng_busy;
  logic        eng_done;
  logic [31:0] eng_baseA, eng_baseB, eng_baseC;
  int unsigned eng_length;

  // engine memory interface nets (same shape as your tb)
  logic [$clog2(MEM_DEPTH)-1:0] eng_raddrA [LANES-1:0];
  logic [$clog2(MEM_DEPTH)-1:0] eng_raddrB [LANES-1:0];
  // engine will read from the same mem_rdataA/B outputs produced by mem_dualport
  // (we'll route addresses to mem_dualport; reads are combinational)
  // so expose wires for clarity:
  wire  word_t eng_rdataA [LANES-1:0];
  wire  word_t eng_rdataB [LANES-1:0];
  logic [LANES-1:0] eng_wen;
  logic [$clog2(MEM_DEPTH)-1:0] eng_waddr [LANES-1:0];
  word_t                        eng_wdata [LANES-1:0];

  // ---------------------------
  // FSM
  // ---------------------------
  typedef enum logic [2:0] { S_IDLE = 3'd0, S_FETCH = 3'd1, S_EXEC = 3'd2, S_ACCEL_WAIT = 3'd3 } state_t;
  state_t state;

  // helper: pack instruction (module-scope function)
  function automatic instr_word_t pack_instr(opcodes_t opc, int dst, int s0, int s1, int imm);
    pack_instr = {opc, dst[5:0], s0[5:0], s1[5:0], imm[7:0]};
  endfunction

  // IMEM init (demo). Testbench may overwrite before pulsing start.
  initial begin
    for (int i = 0; i < IMEM_DEPTH; i++) imem[i] = 32'h0;
    // default tiny demo program (can be replaced by TB)
    imem[0] = pack_instr(OP_ADD,   6'd2, 6'd0, 6'd1, 8'd0);
    imem[1] = pack_instr(OP_LOAD,  6'd4, 6'd0, 6'd0, 8'd2);
    imem[2] = pack_instr(OP_MUL,   6'd5, 6'd2, 6'd4, 8'd0);
    imem[3] = pack_instr(OP_STORE, 6'd0, 6'd5, 6'd0, 8'd16);
  end

  // FETCH/EXEC FSM (sequential)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      pc <= 0;
      fetched_valid <= 1'b0;
      fetched_instr <= '0;
      eng_start <= 1'b0;
    end else begin
      // default clear edge-start
      eng_start <= 1'b0;

      case (state)
        S_IDLE: begin
          fetched_valid <= 1'b0;
          if (start) begin
            pc <= 0;
            state <= S_FETCH;
          end
        end

        S_FETCH: begin
          if (imem[pc] == 32'h0) begin
            fetched_valid <= 1'b0;
            fetched_instr <= '0;
            state <= S_IDLE;
          end else begin
            fetched_instr <= instr_t'(imem[pc]);
            fetched_valid <= 1'b1;
            state <= S_EXEC;
          end
        end

        S_EXEC: begin
          // ACCELERATOR DISPATCH
          if (fetched_valid && cur_opcode == OP_MATADD) begin
            // sample control parameters from lane-0 registers (control-plane)
            // src0 -> baseA, src1 -> baseB, dst -> baseC, imm8 -> length
            eng_baseA  <= regfile[0][cur_src0];
            eng_baseB  <= regfile[0][cur_src1];
            eng_baseC  <= regfile[0][cur_dst];
            eng_length <= cur_immd[7:0];
            eng_start  <= 1'b1; // pulse
            state <= S_ACCEL_WAIT;
          end else begin
            // Normal instruction: advance PC and go FETCH (original behavior)
            if (pc + 1 < IMEM_DEPTH) begin
              pc <= pc + 1;
              state <= S_FETCH;
            end else begin
              fetched_valid <= 1'b0;
              state <= S_IDLE;
            end
          end
        end

        S_ACCEL_WAIT: begin
          // wait for accelerator to finish
          if (eng_done) begin
            if (pc + 1 < IMEM_DEPTH) begin
              pc <= pc + 1;
              state <= S_FETCH;
            end else begin
              fetched_valid <= 1'b0;
              state <= S_IDLE;
            end
          end else begin
            state <= S_ACCEL_WAIT;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // DECODE (combinational): decode the currently-latched instruction
  always_comb begin
    // defaults
    cur_opcode = OP_NOP;
    cur_dst    = 6'd0;
    cur_src0   = 6'd0;
    cur_src1   = 6'd0;
    cur_immd   = 11'd0;

    if (fetched_valid) begin
      instr_t tmp;
      tmp = fetched_instr;
      cur_opcode = tmp.opcode;
      cur_dst    = tmp.dst;
      cur_src0   = tmp.src0;
      cur_src1   = tmp.src1;
      cur_immd   = {{3{1'b0}}, tmp.imm8};
    end
  end

  // Register-file read (combinational)
  always_comb begin
    for (int l = 0; l < LANES; l++) begin
      if (cur_src0 < NUM_REGS) read_reg0[l] = regfile[l][cur_src0];
      else read_reg0[l] = '0;
      if (cur_src1 < NUM_REGS) read_reg1[l] = regfile[l][cur_src1];
      else read_reg1[l] = '0;
    end
  end

  // Instantiate ALUs (per-lane combinational)
  genvar gi;
  generate
    for (gi = 0; gi < LANES; gi++) begin : ALUS
      ALU alu_i (
        .read_reg0    (read_reg0[gi]),
        .read_reg1    (read_reg1[gi]),
        .mem_read_data(mem_rdataA[gi]), // ALU LOAD uses read port A
        .opcode       (cur_opcode),
        .immd         (cur_immd[10:0]),

        .reg_write_en   (alu_reg_write_en[gi]),
        .reg_write_idx  (), // top-level uses cur_dst
        .reg_write_data (alu_reg_write_data[gi]),

        .mem_write_en   (alu_mem_write_en[gi]),
        .mem_write_addr (alu_mem_write_addr[gi]),
        .mem_write_data (alu_mem_write_data[gi])
      );
    end
  endgenerate

  // ---------------------------
  // Memory arbitration / port wiring
  // If engine is busy or starting, give engine exclusive access to scratchpad.
  // Otherwise GPU drives addresses (loads/stores/ALU mem writes).
  // ---------------------------
  always_comb begin
    // default clear
    for (int l = 0; l < LANES; l++) begin
      mem_raddrA[l] = '0;
      mem_raddrB[l] = '0;
      mem_wen[l]    = 1'b0;
      mem_waddr[l]  = '0;
      mem_wdata[l]  = '0;
    end

    if (eng_busy || eng_start) begin
      // engine owns memory
      for (int l = 0; l < LANES; l++) begin
        mem_raddrA[l] = eng_raddrA[l];
        mem_raddrB[l] = eng_raddrB[l];
        mem_wen[l]    = eng_wen[l];
        mem_waddr[l]  = eng_waddr[l];
        mem_wdata[l]  = eng_wdata[l];
      end
    end else begin
      // GPU normal operation
      if (state == S_EXEC && fetched_valid) begin
        for (int l = 0; l < LANES; l++) begin
          if (cur_opcode == OP_LOAD) begin
            mem_raddrA[l] = cur_immd[$clog2(MEM_DEPTH)-1:0]; // broadcast load address
          end

          if (cur_opcode == OP_STORE) begin
            // per-lane store: imm + lane index
            mem_wen[l]   = 1'b1;
            mem_waddr[l] = cur_immd[$clog2(MEM_DEPTH)-1:0] + l;
            mem_wdata[l] = read_reg0[l];
          end else if (alu_mem_write_en[l]) begin
            // fallback if ALU requests mem write directly
            mem_wen[l]   = 1'b1;
            mem_waddr[l] = alu_mem_write_addr[l];
            mem_wdata[l] = alu_mem_write_data[l];
          end
        end
      end
    end
  end

  // Scratchpad memory instantiation (internal mem_dualport)
  mem_dualport #(.ADDR_WIDTH($clog2(MEM_DEPTH))) scratchpad (
    .clk        (clk),
    .write_en   (mem_wen),
    .write_addr (mem_waddr),
    .write_data (mem_wdata),
    .read_addr_a(mem_raddrA),
    .read_data_a(mem_rdataA),
    .read_addr_b(mem_raddrB),
    .read_data_b(mem_rdataB)
  );

  // Route mem_dualport read data to engine read data wires
  assign eng_rdataA = mem_rdataA;
  assign eng_rdataB = mem_rdataB;

  // ---------------------------
  // Instantiate MatrixAddEngine accelerator
  // signature assumed to match the testbench: see tb_matadd
  // ---------------------------
  MatrixAddEngine #(.LANES(LANES)) matadd_accel (
    .clk(clk), .rst_n(rst_n),
    .start(eng_start),
    .baseA(eng_baseA), .baseB(eng_baseB), .baseC(eng_baseC), .length(eng_length),
    .busy(eng_busy), .done(eng_done),
    .mem_raddrA(eng_raddrA), .mem_raddrB(eng_raddrB),
    .mem_rdataA(eng_rdataA), .mem_rdataB(eng_rdataB),
    .mem_wen(eng_wen), .mem_waddr(eng_waddr), .mem_wdata(eng_wdata)
  );

  // WRITEBACK: perform register writes at posedge during S_EXEC
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int l = 0; l < LANES; l++)
        for (int r = 0; r < NUM_REGS; r++)
          regfile[l][r] <= '0;
    end else begin
      // Only commit writes when the machine is in EXEC and fetched_valid.
      if (state == S_EXEC && fetched_valid) begin
        for (int l = 0; l < LANES; l++) begin
          if (alu_reg_write_en[l]) begin
            if (cur_dst < NUM_REGS) regfile[l][cur_dst] <= alu_reg_write_data[l];
          end
        end
      end
    end
  end

  // Small debug print for trace (can be removed in long runs)
  always_ff @(posedge clk) begin
    if (fetched_valid) begin
      $display("%0t: [STATE=%0d] PC=%0d OPC=%0d DST=%0d IMM=%0d",
               $time, state, pc, cur_opcode, cur_dst, cur_immd);
    end else begin
      if (state == S_IDLE) $display("%0t: [IDLE] PC=%0d", $time, pc);
    end
  end

endmodule
