module simd_div32 (
    input  logic [31:0] a_input, b_input,
    output logic [31:0] result
);
    assign result = (b_input == 0) ? 32'hFFFFFFFF : a_input / b_input;
    // (read_reg1 != 0) ? (read_reg0 / read_reg1) : 32'hFFFF_FFFF;
endmodule