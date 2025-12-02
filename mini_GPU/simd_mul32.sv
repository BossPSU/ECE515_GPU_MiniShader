module simd_mul32 (
    input  logic [31:0] a_input, b_input,
    output logic [31:0] result
);
    assign result = a_input * b_input;
endmodule