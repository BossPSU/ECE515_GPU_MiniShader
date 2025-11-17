GPU shader (8 cores, 64 32-bit registers)

inputs: 
-one line of ISA, stored as a 32bit instruction
-64 register array, each 32 bits

output:
-64 register array, each 32 bits

Steps:
1-Decode
Instruction is decoded based on its bits
[31:26] - Opcode for ALU
[25:21] - location of destination register
[20:16] - location of source1 register
[15:11] - location of source2 register
[10:0] - unused/immediate

2-ALU 
ALU runs an operation on 2 source registers based on opcode, outputs destination register
output register array is then updated with destination register

To/do
-add test bench
-add PLC???
  -4-1 Mux (normal, jump, branch, stall > next)
