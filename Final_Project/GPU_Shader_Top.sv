// GPU_Shader.sv
import GPU_Shader_pkg::*;
import opcode_pkg::*; // assume opcodes like OP_LOAD, OP_STORE, OP_ADD exist

module GPU_Shader
  ( input  logic            clk,
    input  logic [31:0]     instr  [lanes-1:0],
    input  word_t           regfile [lanes-1:0][63:0], // regfile[lane][reg_index]
    output word_t           write_reg_out [lanes-1:0][63:0] // writeback per-lane (optional)
  );

  // ------------------------------------------------------------
  // decode outputs (per-lane)
  // ------------------------------------------------------------
  logic [5:0]  opcode   [lanes-1:0];
  logic [4:0]  dst      [lanes-1:0];
  logic [4:0]  src0     [lanes-1:0];
  logic [4:0]  src1     [lanes-1:0];
  logic [10:0] immd     [lanes-1:0];

  // instantiate decode module (assumes decode has same port names)
  decode dec (
    .instr(instr),
    .opcode(opcode),
    .dst(dst),
    .src0(src0),
    .src1(src1),
    .immd(immd)
  );

  // ------------------------------------------------------------
  // dual-ported scratchpad: single bank with two read ports per lane + writes per lane
  // ------------------------------------------------------------
  localparam int AW = $clog2(MEM_DEPTH);

  logic [AW-1:0] mem_raddr_a [lanes-1:0];
  logic [AW-1:0] mem_raddr_b [lanes-1:0];
  word_t         mem_rdata_a [lanes-1:0];
  word_t         mem_rdata_b [lanes-1:0];

  logic [lanes-1:0]              mem_wen;
  logic [AW-1:0]                 mem_waddr [lanes-1:0];
  word_t                         mem_wdata [lanes-1:0];

  // dual-ported memory instance (reads combinational, writes synchronous)
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
  // instantiate ALUs per lane
  // ------------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < lanes; i++) begin : lanes_block
      // Connect ALU inputs:
      // - For register-ALU ops, use the regfile values
      // - For load/store, layers use mem read ports (we'll set mem_raddr_a/b below)
      //
      // ALU interface we expect (example):
      // ALU ( .clk(clk),
      //       .read_reg0(word_t), .read_reg1(word_t),
      //       .mem_read_data(word_t), // optional
      //       .opcode(logic [5:0]),
      //       .immd(logic [10:0]),
      //       .mem_write_en(output), .mem_write_addr(output), .mem_write_data(output),
      //       .write_reg(output)
      // );
      //
      // We'll instantiate a symmetric ALU that can request a mem write (STORE) or use mem read as source (LOAD).

      // local per-lane wires for ALU connection
      word_t alu_read0;
      word_t alu_read1;
      word_t alu_write_result;

      // Choose ALU operand sources (here: primarily from regfile; you can change to mem reads)
      // dynamic indexing into regfile using src field
      assign alu_read0 = regfile[i][ src0[i] ];
      assign alu_read1 = regfile[i][ src1[i] ];

      // instantiate ALU (you must have an ALU with this port ordering)
      ALU alu_i (
        .clk          (clk),
        .read_reg0    (alu_read0),
        .read_reg1    (alu_read1),
        .mem_read_data(mem_rdata_a[i]), // choose mem port A as ALU's optional mem input (for LOAD)
        .opcode       (opcode[i]),
        .immd         (immd[i]),
        .mem_write_en (mem_wen[i]),
        .mem_write_addr(mem_waddr[i]),
        .mem_write_data(mem_wdata[i]),
        .write_reg    (alu_write_result)
      );

      // writeback into host-visible write_reg_out (indexed by dst)
      // If your write_reg_out is a set of registers per-lane, set the destination accordingly.
      // Here we write the ALU result into the per-lane dst index.
      // Because write_reg_out is a 2D array, we use procedural assignment in always_comb
      always_comb begin
        // default: keep previous or 0
        write_reg_out[i] = '0; // zero all reg entries by default
        // write single destination register
        // Note: this is a simplified model. In a real design you'd do register-file writeback synchronously.
        write_reg_out[i][ dst[i] ] = alu_write_result;
      end

      // ------------------------------------------------------------
      // Memory address selection for this lane (simple example)
      // ------------------------------------------------------------
      // Example ISA conventions (adapt to your encoding):
      // - OP_LOAD: immd holds memory address; result -> write_reg
      // - OP_STORE: mem_write_en asserted by ALU; write_data from read_reg0
      //
      // For matrix-add engine you would set mem_raddr_a and mem_raddr_b based on immd or src.
      always_comb begin
        // default addresses (avoid X)
        mem_raddr_a[i] = '0;
        mem_raddr_b[i] = '0;

        // Simple example semantics:
        // Use immediate as memory address for LOAD/STORE, else leave addresses 0.
        if (opcode[i] == OP_LOAD) begin
          mem_raddr_a[i] = immd[i][AW-1:0]; // read A from address in immediate
        end else if (opcode[i] == OP_STORE) begin
          // For store we want to write reg0 into mem: ALU sets mem_wen/address/data
          // However we can still optionally read another mem addr into mem_rdata_b
          mem_raddr_a[i] = '0;
        end else begin
          // For normal ALU ops we might not need memory access
          mem_raddr_a[i] = '0;
          mem_raddr_b[i] = '0;
        end

        // Example: if you want ALU to fetch a second memory source (B) from src1/immd or similar, set mem_raddr_b
        // mem_raddr_b[i] = some_other_addr;
      end

    end
  endgenerate

endmodule
