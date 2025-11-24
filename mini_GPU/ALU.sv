
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
        reg_write_data = read_reg0 + read_reg1;
      end
      OP_SUB: begin
        reg_write_en   = 1'b1;
        reg_write_data = read_reg0 - read_reg1;
      end
      OP_MUL: begin
        reg_write_en   = 1'b1;
        reg_write_data = read_reg0 * read_reg1;
      end
      OP_DIV: begin
        reg_write_en   = 1'b1;
        reg_write_data = (read_reg1 != 0) ? (read_reg0 / read_reg1) : 32'hFFFF_FFFF;
      end
      OP_MIN: begin
        reg_write_en   = 1'b1;
        reg_write_data = (read_reg0 < read_reg1) ? read_reg0 : read_reg1;
      end
      OP_MAX: begin
        reg_write_en   = 1'b1;
        reg_write_data = (read_reg0 > read_reg1) ? read_reg0 : read_reg1;
      end
      OP_AND: begin
        reg_write_en   = 1'b1;
        reg_write_data = read_reg0 & read_reg1;
      end
      OP_OR: begin
        reg_write_en   = 1'b1;
        reg_write_data = read_reg0 | read_reg1;
      end
      OP_XOR: begin
        reg_write_en   = 1'b1;
        reg_write_data = read_reg0 ^ read_reg1;
      end
      OP_XNOR: begin
        reg_write_en   = 1'b1;
        reg_write_data = ~(read_reg0 ^ read_reg1);
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
