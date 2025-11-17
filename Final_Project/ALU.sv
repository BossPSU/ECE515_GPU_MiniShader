import opcode_pkg::*;
module ALU(input logic [31:0] read_reg0,read_reg1, input logic [5:0] opcode, output logic [31:0] write_reg;

	opcodes op;
	always_comb op = opcodes'(opcode);

	always_comb begin
		case(op) //update with correct arithmetic/logic
			ADD: write_reg = read_reg0+read_reg1,
			SUB: write_reg = read_reg0+read_reg1,
			MUL: write_reg = read_reg0+read_reg1,
			DIV: write_reg = read_reg0+read_reg1,
			MIN: write_reg = read_reg0+read_reg1,
			MAX: write_reg = read_reg0+read_reg1,
			AND: write_reg = read_reg0+read_reg1,
			OR: write_reg = read_reg0+read_reg1,
			XOR: write_reg = read_reg0+read_reg1,
			XAND write_reg = read_reg0+read_reg1, 
			default: write_reg = write_reg;
		endcase
	end
endmodule
		
		
