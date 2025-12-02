
// ALU.sv
import GPU_Shader_pkg::*;
import opcode_pkg::*;
module ALU
  (
    input  word_t        read_reg0,      // operand
    input  word_t        read_reg1,      // operand
    input  word_t        mem_read_data,  // memory data (for LOAD)
    input  opcodes_t     opcode,
    input  logic [10:0]  immd,           // immediate field
    // outputs
    output logic         reg_write_en,   // writeback enable to regfile
    output int unsigned  reg_write_idx,  // register index (0..NUM_REGS-1)
    output word_t        reg_write_data, // data to write back
    // memory write request (STORE)
    output logic         mem_write_en,
    output logic [$clog2(MEM_DEPTH)-1:0] mem_write_addr,
    output word_t        mem_write_data
  );

  word_t op_add, op_sub, op_mul, op_div;
  word_t op_min, op_max;
  word_t op_and, op_or, op_xor, op_xnor;
  
  // instantiate simd_add32 for addition
  simd_add32 U_ADD32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_add));
  // instantiate simd_sub32 for subtraction
  simd_sub32 U_SUB32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_sub));
  // multiply, divide, min, max
  simd_mul32 U_MUL32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_mul));
  simd_div32 U_DIV32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_div));
  simd_min32 U_MIN32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_min));
  simd_max32 U_MAX32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_max));
  // bitwise operations
  simd_and32 U_AND32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_and));
  simd_or32  U_OR32  (.a_input(read_reg0), .b_input(read_reg1), .result(op_or));
  simd_xor32 U_XOR32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_xor));
  simd_xnor32 U_XNOR32 (.a_input(read_reg0), .b_input(read_reg1), .result(op_xnor));


  // defaults
  always_comb begin
    reg_write_en     = 1'b0;
    reg_write_idx    = 0;
    reg_write_data   = '0;
    mem_write_en     = 1'b0;
    mem_write_addr   = '0;
    mem_write_data   = '0;

    case (opcode)
      OP_ADD: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_add;
      end
      OP_SUB: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_sub;
      end
      OP_MUL: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_mul;
      end
      OP_DIV: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_div;
      end
      OP_MIN: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_min;
      end
      OP_MAX: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_max;
      end
      OP_AND: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_and;
      end
      OP_OR: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_or;
      end
      OP_XOR: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_xor;
      end
      OP_XNOR: begin
        reg_write_en   = 1'b1;
        reg_write_data = op_xnor;
      end
      OP_LOAD: begin
        // LOAD: result is memory data
        reg_write_en   = 1'b1;
        reg_write_data = mem_read_data;
      end
      OP_STORE: begin
        // STORE: write reg0 into memory at immediate address (immd truncated)
        mem_write_en   = 1'b1;
        mem_write_addr = immd[$clog2(MEM_DEPTH)-1:0];
        mem_write_data = read_reg0;
      end
      default: begin
        reg_write_en = 1'b0;
      end
    endcase

    // the destination register index is provided by the caller (top-level),
    // so here we don't set reg_write_idx. The top-level will use dst field to write to regfile.
  end

endmodule
