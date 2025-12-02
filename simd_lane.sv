// -------------------------------
// Per-lane module: supports ADD/SUB/MUL/DIV (unsigned)
// Each micro-step is one bit (MSB-first for DIV, LSB/bit-index used for MUL/ADD)
// -------------------------------

`timescale 1ns/1ps

module simd_lane #(
    parameter int WIDTH = 32
)(
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     start_bit,   // asserted for the bit micro-step
    input  logic [$clog2(WIDTH)-1:0] bit_idx,     // which bit in 0..WIDTH-1
    input  logic                     start_op,    // pulse to load operands

    input  logic [1:0]               op,          // operation code

    input  logic [WIDTH-1:0]         a_in,
    input  logic [WIDTH-1:0]         b_in,

    output logic [WIDTH-1:0]         result_out,
    output logic                     done_bit,    // pulses when this micro-step is complete
    output logic                     div_by_zero
);

    localparam logic [1:0] OP_ADD = 2'd0;
    localparam logic [1:0] OP_SUB = 2'd1;
    localparam logic [1:0] OP_MUL = 2'd2;
    localparam logic [1:0] OP_DIV = 2'd3;

    // Internal registers
    logic [WIDTH-1:0] A_reg, B_reg;
    logic a_bit, b_bit, sum_bit;
    // ADD/SUB
    logic [WIDTH:0] carry;          // carry chain for add/sub
    logic [WIDTH-1:0] sum_reg;

    // MUL
    logic [2*WIDTH-1:0] prod_reg;   // accumulator for iterative multiply

    // DIV (restoring)
    logic [WIDTH-1:0] dividend_reg;
    logic [WIDTH-1:0] divisor_reg;
    logic [WIDTH:0]     rem;        // N+1 bits
    logic [WIDTH-1:0]   q_reg;
    logic               dbz;        // div-by-zero flag

    // Done register (pulsed when start_bit happens and computation completes)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            A_reg      <= '0;
            B_reg      <= '0;
            carry      <= '0;
            sum_reg    <= '0;
            prod_reg   <= '0;
            dividend_reg <= '0;
            divisor_reg  <= '0;
            rem        <= '0;
            q_reg      <= '0;
            dbz        <= 1'b0;
            done_bit   <= 1'b0;
            result_out <= '0;
        end else begin
            // clear done bit by default; it will be set when start_bit triggers a microstep
            done_bit <= 1'b0;

            // Load operands at operation start
            if (start_op) begin
                A_reg <= a_in;
                B_reg <= b_in;
                // initialize for add/sub
                carry <= '0;
                sum_reg <= '0;
                // init multiply
                prod_reg <= '0;
                // init divide
                dividend_reg <= a_in;
                divisor_reg  <= b_in;
                rem <= '0;
                q_reg <= '0;
                dbz <= (b_in == {WIDTH{1'b0}});
            end
            else if (start_bit) begin
                // Perform one micro-step depending on operation
                unique case (op)
                    OP_ADD, OP_SUB: begin

                        // For SUB, implement A + (~B) + 1 by inverting B bits and setting initial carry[0]=1 at load time.
                        // We'll consider carry[0] seeded at load time for SUB: set carry[0]=1 when start_op occurs.
                        // But to keep pipeline simple: on first bit (bit_idx==0) we set carry[0] appropriately if op==SUB.
                        if (bit_idx == 0) begin
                            if (op == OP_SUB)
                                carry[0] <= 1'b1; // seed subtract carry-in (twos comp)
                            else
                                carry[0] <= 1'b0;
                        end

                        // compute this bit
                        a_bit <= A_reg[bit_idx];
                        b_bit <= (op == OP_SUB) ? ~B_reg[bit_idx] : B_reg[bit_idx];
                        #1;
                        $display("In microstep: a_bit: %0d, b_bit: %0d", a_bit, b_bit);

                        // sum bit = a ^ b ^ carry
                        sum_bit <= a_bit ^ b_bit ^ carry[bit_idx];
                        #1;
                        $display("In microstep: sum_bit: %0d, carry_in: %0d", sum_bit, carry[bit_idx]);
                        sum_reg[bit_idx] <= sum_bit;
                        //#5;
                        $display("In microstep: sum_reg[%0d]: %0d", bit_idx, sum_reg[bit_idx]);

                        // carry-out
                        carry[bit_idx+1] <= (a_bit & b_bit) | (a_bit & carry[bit_idx]) | (b_bit & carry[bit_idx]);
                        $display("In microstep: carry_out: %0d", carry[bit_idx+1]);

                        // Indicate micro-step done
                        done_bit <= 1'b1;

                        // If last bit, pack result
                        if (bit_idx == WIDTH-1) begin
                            result_out <= sum_reg;
                        end
                    end

                    OP_MUL: begin
                        // iterative shift-add: if B_reg[bit_idx] == 1, add (A_reg << bit_idx) to prod_reg
                        if (B_reg[bit_idx]) begin
                            prod_reg <= prod_reg + ( (unsigned'(A_reg)) << bit_idx );
                        end
                        done_bit <= 1'b1;
                        if (bit_idx == WIDTH-1) begin
                            result_out <= prod_reg[WIDTH-1:0]; // lower WIDTH bits as product
                        end
                    end

                    OP_DIV: begin
                        if (dbz) begin
                            // Division-by-zero policy: quotient := all ones, remainder := dividend
                            q_reg[WIDTH-1 - bit_idx] <= 1'b1;
                            rem <= {1'b0, dividend_reg}; // remainder becomes dividend
                            done_bit <= 1'b1;
                            if (bit_idx == WIDTH-1) begin
                                result_out <= {WIDTH{1'b1}}; // quotient all ones
                            end
                        end else begin
                            // restoring division MSB-first:
                            // shift rem left and bring in dividend MSB at position (WIDTH-1 - bit_idx)
                            logic bit_in;
                            logic [WIDTH:0] rem_shifted;
                            logic [WIDTH:0] trial;

                            bit_in = dividend_reg[WIDTH-1 - bit_idx];
                            rem_shifted = {rem[WIDTH-1:0], bit_in};

                            trial = rem_shifted - {1'b0, divisor_reg};
                            if (!trial[WIDTH]) begin
                                // trial >= 0
                                rem <= trial;
                                q_reg[WIDTH-1 - bit_idx] <= 1'b1;
                            end else begin
                                // trial < 0 -> keep shifted rem (already assigned to rem non-blocking)
                                rem <= rem_shifted;
                                q_reg[WIDTH-1 - bit_idx] <= 1'b0;
                            end

                            done_bit <= 1'b1;

                            if (bit_idx == WIDTH-1) begin
                                result_out <= q_reg;
                            end
                        end
                    end

                    default: begin
                        done_bit <= 1'b1;
                    end
                endcase
            end
        end
    end

    // Expose div-by-zero
    assign div_by_zero = dbz;

endmodule