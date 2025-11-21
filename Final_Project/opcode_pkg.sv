// package opcode_pkg;

// 	typedef enum logic [5:0] {
// 	ADD = 5'b00000, 
// 	SUB = 5'b00001, 
// 	MUL = 5'b00010, 
// 	DIV = 5'b00011
// 	MIN = 5'b00100,
// 	MAX = 5'b00101,
// 	AND = 5'b00110,
// 	OR = 5'b00111,
// 	XOR = 5'b01000,
// 	XAND = 5'b01001
// 	} opcodes;
	

// endpackage : opcode_pkg


package opcode_pkg;
  typedef enum logic [5:0] {
    OP_NOP = 6'd0,
    OP_ADD = 6'd1,
    OP_SUB = 6'd2,
    OP_MUL = 6'd3,
    OP_DIV = 6'd4,
    OP_LOAD = 6'd10,    // load from memory
    OP_STORE = 6'd11,   // store to memory
    OP_MAX = 6'd63
  } opcodes;
endpackage
