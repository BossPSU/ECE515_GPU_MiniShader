package opcode_pkg;

	typedef enum logic [5:0] {
	ADD = 5'b00000, 
	SUB = 5'b00001, 
	MUL = 5'b00010, 
	DIV = 5'b00011
	MIN = 5'b00100,
	MAX = 5'b00101,
	AND = 5'b00110,
	OR = 5'b00111,
	XOR = 5'b01000,
	XAND = 5'b01001
	} opcodes;
	

endpackage : opcode_pkg
