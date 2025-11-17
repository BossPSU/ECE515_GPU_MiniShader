import opcode_pkg::*;
import GPU_Shader_pkg::*;
module GPU_Shader(input logic [31:0] instr [lanes-1:0], input logic [31:0] read_reg [lanes-1][63:0], output logic [31:0] write_reg [lanes-1][63:0]);

	logic [5:0] opcode [lanes-1:0];
	logic [4:0] (dst, src0, src1) [lanes-1:0];
	logic [10:0] immd [lanes-1:0];

	//decode and compute output
	decode decode(.*);
	ALU ALU0(read_reg[0][src0],read_reg[0][src1],opcode[0], write_reg[0][dst]);
	ALU ALU1(read_reg[1][src0],read_reg[1][src1],opcode[1], write_reg[1][dst]);
	//continue until ALU# = lane#

endmodule
