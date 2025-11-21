// ALU.sv
import opcode_pkg::*;
import GPU_Shader_pkg::*; // for word_t and MEM_DEPTH

module ALU ( input  logic            clk,                // optional clock (unused here but kept for uniform interface)
    input  word_t           read_reg0,          // operand 0 (usually register)
    input  word_t           read_reg1,          // operand 1 (usually register)
    input  word_t           mem_read_data,      // data read from memory (for LOAD)
    input  logic  [5:0]     opcode,             // 6-bit opcode
    input  logic [10:0]     immd,               // immediate field (narrow example)
    output logic            mem_write_en,      // assert to request a memory write
    output logic [$clog2(MEM_DEPTH)-1:0] mem_write_addr, // address for memory write
    output word_t           mem_write_data,     // data to write to memory
    output word_t           write_reg           // value to write back to register file (or host)
);

  // Cast opcode bits into enum type defined in opcode_pkg.
  // Adjust the enum type name if your package uses a different typedef name.
  opcodes_t op = opcodes_t'(opcode);

  // default outputs
  always_comb begin
    // defaults
    mem_write_en   = 1'b0;
    mem_write_addr = '0;
    mem_write_data = '0;
    write_reg      = '0;

    case (op)
      OP_ADD:  write_reg = read_reg0 + read_reg1;
      OP_SUB:  write_reg = read_reg0 - read_reg1;
      OP_MUL:  write_reg = read_reg0 * read_reg1;
      OP_DIV:  write_reg = (read_reg1 != 0) ? (read_reg0 / read_reg1) : 32'hFFFF_FFFF; // sentinel on div0
      OP_MIN:  write_reg = (read_reg0 < read_reg1) ? read_reg0 : read_reg1;
      OP_MAX:  write_reg = (read_reg0 > read_reg1) ? read_reg0 : read_reg1;
      OP_AND:  write_reg = read_reg0 & read_reg1;
      OP_OR:   write_reg = read_reg0 | read_reg1;
      OP_XOR:  write_reg = read_reg0 ^ read_reg1;
      OP_XNOR: write_reg = ~(read_reg0 ^ read_reg1);

      // LOAD: return the memory read data (assumes top-level provided mem_read_data)
      OP_LOAD: begin
        write_reg = mem_read_data;
      end

      // STORE: request a memory write (value taken from read_reg0, address from immediate)
      OP_STORE: begin
        mem_write_en   = 1'b1;
        // truncate immediate to address width; you can change this to use a register index instead
        mem_write_addr = immd[$clog2(MEM_DEPTH)-1:0];
        mem_write_data = read_reg0;
        write_reg      = '0; // store doesn't write a register (or could write status)
      end

      default: begin
        // unknown op -> return zero
        write_reg = '0;
      end
    endcase
  end

endmodule
