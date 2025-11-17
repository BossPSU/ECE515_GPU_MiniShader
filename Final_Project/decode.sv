import GPU_Shader_pkg::*;
module decode(
	input logic [31:0] instr [lanes-1:0],
	output logic [5:0] opcode [lanes-1:0],
	output logic [4:0] (dst,src0,src1) [lanes-1:0],
	output logic [10:0] immd [lanes-1:0]
	);
	
	for (int i = 0; i<lanes; i++)begin
		opcode[i] = instr[i][31:26];
		dst[i] = instr[i][25:21];
		src0[i] = instr[i][20:16];
		src1[i] = instr[i][15:11];
		immd[i] = instr[i][10:0];
	end
	
endmodule
