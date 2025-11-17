package GPU_Shader_pkg;

	parameter int num_reg = 32;
	parameter int num_reg_inBits = $clog2(num_reg);
	parameter int instr_bits = 32;
	parameter int lanes = 8;
	parameter int op_bits = 6;
	parameter int reg_bits = 5;

endpackage : GPU_Shader_pkg
	
	
