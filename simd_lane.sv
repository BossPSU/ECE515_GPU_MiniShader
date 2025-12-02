// -------------------------------
// Per-lane module: supports ADD/SUB/MUL/DIV (unsigned)
// Each micro-step is one bit (MSB-first for DIV, LSB/bit-index used for MUL/ADD)
// -------------------------------

`timescale 1ns/1ps

module simd_lane #(
    parameter int BIT_WIDTH = 32
)(
    input  logic                     clk,
    input  logic                     reset,
    input  logic                     start_bit,   // asserted for the bit micro-step
    input  logic [$clog2(BIT_WIDTH)-1:0] bit_select,     // which bit in 0..BIT_WIDTH-1
    input  logic                     start_op,    // pulse to load operands

    input  logic [1:0]               op_code,          // operation code

    input  logic [BIT_WIDTH-1:0]         a_input,
    input  logic [BIT_WIDTH-1:0]         b_input,

    output logic [BIT_WIDTH-1:0]         result_out,
    output logic                     done_bit,    // pulses when this micro-step is complete
    output logic                     div_by_zero
);

    localparam logic [1:0] OP_ADD = 2'd0;
    localparam logic [1:0] OP_SUB = 2'd1;
    localparam logic [1:0] OP_MUL = 2'd2;
    localparam logic [1:0] OP_DIV = 2'd3;

    //logic a_bit, b_bit;
    //logic sum_bit;

    // Internal registers
    logic [BIT_WIDTH-1:0] A_reg, B_reg;
    // ADD/SUB
    logic [BIT_WIDTH:0] carry;          // carry chain for add/sub
    logic [BIT_WIDTH-1:0] sum_reg;

    // MUL
    logic [2*BIT_WIDTH-1:0] prod_reg;   // accumulator for iterative multiply

    // DIV (restoring)
    logic [BIT_WIDTH-1:0] dividend_reg;
    logic [BIT_WIDTH-1:0] divisor_reg;
    logic [BIT_WIDTH:0]     rem;        // N+1 bits
    logic [BIT_WIDTH-1:0]   quotient_reg;
    logic               dbz;        // div-by-zero flag

    // Done register (pulsed when start_bit happens and computation completes)
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            A_reg      <= '0;
            B_reg      <= '0;
            carry      <= '0;
            sum_reg    <= '0;
            prod_reg   <= '0;
            dividend_reg <= '0;
            divisor_reg  <= '0;
            rem        <= '0;
            quotient_reg <= '0;
            dbz        <= 1'b0;
            done_bit   <= 1'b0;
            result_out <= '0;
        end else begin
            // clear done bit by default; it will be set when start_bit triggers a microstep
            done_bit <= 1'b0;

            // Load operands at operation start
            if (start_op) begin
                // Load operands into registers
                A_reg <= a_input;
                B_reg <= b_input;
                // initialize other registers
                carry <= '0;
                sum_reg <= '0;
                prod_reg <= '0;
                dividend_reg <= a_input;
                divisor_reg  <= b_input;
                rem <= '0;
                quotient_reg <= '0;
                dbz <= (b_input == {BIT_WIDTH{1'b0}});
            end
            else if (start_bit) begin
                // Perform one micro-step depending on operation
                unique case (op_code)
                    OP_ADD, OP_SUB: begin

                        logic a_bit, b_bit, sum_bit;
                        // For SUB, implement A + (~B) + 1 by inverting B bits and setting initial carry[0]=1 at load time.
                        // We'll consider carry[0] seeded at load time for SUB: set carry[0]=1 when start_op occurs.
                        // But to keep pipeline simple: on first bit (bit_select==0) we set carry[0] appropriately if op==SUB.

                        $display("In ADD/SUB microstep: A reg: %0d, B reg: %0d", A_reg, B_reg);
                        if (bit_select == 0) begin
                            if (op_code == OP_SUB)
                                carry[0] <= 1'b1; // seed subtract carry-in (twos comp)
                            else
                                carry[0] <= 1'b0;
                        end

                        // compute this bit
                        a_bit = A_reg[bit_select];
                        b_bit = (op_code == OP_SUB) ? ~B_reg[bit_select] : B_reg[bit_select];
                        #5; // wait for a_bit, b_bit to settle
                        $display("In microstep: a_bit: %0d, b_bit: %0d", a_bit, b_bit);
                        //logic a_bit, b_bit, sum_bit;
                        //a_bit <= A_reg[bit_select];
                        //b_bit <= (op_code == OP_SUB) ? ~B_reg[bit_select] : B_reg[bit_select];
                        //$display("In microstep: a_bit: %0d, b_bit: %0d", a_bit, b_bit);

                        sum_bit = a_bit ^ b_bit ^ carry[bit_select];
                        #5; // wait for sum_bit to settle
                        $display("Computed sum_bit: %0d", sum_bit);

                        //sum_reg[bit_select] <= A_reg[bit_select] ^ ((op_code == OP_SUB) ? ~B_reg[bit_select] : B_reg[bit_select]) ^ carry[bit_select];
                        //$display("Computed sum_reg[%0d]: %0d", bit_select, sum_reg[bit_select]);
                        
                        //$display("sum_bit after #5 delay: %0d", sum_bit);
                        //sum_reg[bit_select] <= a_bit ^ b_bit ^ carry[bit_select];
                        //$display("Computed sum_bit: %0d", sum_bit);
                        //#5; // wait for sum_bit to settle
                        sum_reg[bit_select] = sum_bit;
                        $display("sum_reg[%0d] immediately after microstep in assignment: %0d", bit_select, sum_reg[bit_select]);

                        #5; // wait for sum_reg assignment to settle

                        // carry-out
                        carry[bit_select+1] = (a_bit & b_bit) | (a_bit & carry[bit_select]) | (b_bit & carry[bit_select]);
                        /**
                        carry[bit_select+1] <= (A_reg[bit_select] & ((op_code == OP_SUB) ? ~B_reg[bit_select] : B_reg[bit_select])) |
                                          (A_reg[bit_select] & carry[bit_select]) |
                                          (((op_code == OP_SUB) ? ~B_reg[bit_select] : B_reg[bit_select]) & carry[bit_select]);
                                          **/
                        
                        #5; // wait for carry to settle
                        
                        $display("Computed carry[%0d]: %0d", bit_select+1, carry[bit_select+1]);

                        // Indicate micro-step done
                        done_bit <= 1'b1;
                        // If last bit, pack result
                        if (bit_select == BIT_WIDTH-1) begin
                            result_out <= sum_reg;
                            $display("Final sum_reg result: %0d", sum_reg);
                            $display("Final written result_out: %0d", result_out);
                        end
                    end

                    OP_MUL: begin
                        // iterative shift-add: if B_reg[bit_select] == 1, add (A_reg << bit_select) to prod_reg
                        if (B_reg[bit_select]) begin
                            prod_reg = prod_reg + ( (unsigned'(A_reg)) << bit_select );
                        end
                        done_bit = 1'b1;
                        if (bit_select == BIT_WIDTH-1) begin
                            result_out = prod_reg[BIT_WIDTH-1:0]; // lower BIT_WIDTH bits as product
                        end
                    end

                    OP_DIV: begin
                        if (dbz) begin
                            // Division-by-zero policy: quotient := all ones, remainder := dividend
                            quotient_reg[BIT_WIDTH-1 - bit_select] = 1'b1;
                            rem = {1'b0, dividend_reg}; // remainder becomes dividend
                            done_bit = 1'b1;
                            if (bit_select == BIT_WIDTH-1) begin
                                result_out = {BIT_WIDTH{1'b1}}; // quotient all ones
                            end
                        end else begin
                            // restoring division MSB-first:
                            // shift rem left and bring in dividend MSB at position (BIT_WIDTH-1 - bit_select)
                            logic bit_in;
                            logic [BIT_WIDTH:0] rem_shifted;
                            logic [BIT_WIDTH:0] trial;

                            bit_in = dividend_reg[BIT_WIDTH-1 - bit_select];
                            rem_shifted = {rem[BIT_WIDTH-1:0], bit_in};

                            trial = rem_shifted - {1'b0, divisor_reg};
                            if (!trial[BIT_WIDTH]) begin
                                // trial >= 0
                                rem = trial;
                                quotient_reg[BIT_WIDTH-1 - bit_select] = 1'b1;
                            end else begin
                                // trial < 0 -> keep shifted rem (already assigned to rem non-blocking)
                                rem = rem_shifted;
                                quotient_reg[BIT_WIDTH-1 - bit_select] = 1'b0;
                            end

                            done_bit = 1'b1;

                            if (bit_select == BIT_WIDTH-1) begin
                                result_out = quotient_reg;
                            end
                        end
                    end

                    default: begin
                        done_bit = 1'b1;
                    end
                endcase
                $display("At end of microstep: result_out: %0d, done_bit: %0d", result_out, done_bit);

            end
        end
    end

    // Expose div-by-zero
    assign div_by_zero = dbz;

endmodule