
// opcode_pkg.sv
package opcode_pkg;
  typedef enum logic [5:0] {
    OP_NOP    = 6'd0,
    OP_ADD    = 6'd1,
    OP_SUB    = 6'd2,
    OP_MUL    = 6'd3,
    OP_DIV    = 6'd4,
    OP_MIN    = 6'd5,
    OP_MAX    = 6'd6,
    OP_AND    = 6'd7,
    OP_OR     = 6'd8,
    OP_XOR    = 6'd9,
    OP_XNOR   = 6'd10,
    OP_LOAD   = 6'd16,
    OP_STORE  = 6'd17,
    OP_MATADD = 6'd32,  // special accelerator instruction
    OP_MATMUL = 6'd33   // matrix multiplication accelerator
  } opcodes_t;
endpackage
