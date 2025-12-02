// simd_lockstep_alu.sv
`timescale 1ns/1ps

module simd_lockstep_alu #(
    parameter int LANES = 4,
    parameter int BIT_WIDTH = 32
)(
    input  logic                     clk,
    input  logic                     reset,

    // Control
    input  logic                     start,    // pulse to start the SIMD op
    output logic                     done,     // pulses when whole vector op done
    input  logic [1:0]               op_code,       // operation code

    // Per-lane operands (unsigned)
    input  logic [LANES-1:0][BIT_WIDTH-1:0] a,
    input  logic [LANES-1:0][BIT_WIDTH-1:0] b,

    // Results per-lane
    output logic [LANES-1:0][BIT_WIDTH-1:0] result,
    // Extra per-lane flags (division)
    output logic [LANES-1:0]            div_by_zero
);

    // Operation encoding
    localparam logic [1:0] OP_ADD = 2'd0;
    localparam logic [1:0] OP_SUB = 2'd1;
    localparam logic [1:0] OP_MUL = 2'd2;
    localparam logic [1:0] OP_DIV = 2'd3;

    // ------------------------
    // Lockstep controller FSM
    // ------------------------
    typedef enum logic [1:0] {IDLE, START_BIT, WAIT_BIT, FINISHED} state_t;
    state_t state, next;

    logic [$clog2(BIT_WIDTH)-1:0] bit_select;
    logic start_bit;                       // broadcast start for current micro-step
    logic [LANES-1:0] lane_done;           // per-lane done for current bit
    logic start_op_pulse;                  // pulse to load operands at op start

    // FSM / bit index registers
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state   <= IDLE;
            bit_select <= '0;
        end else begin
            state <= next;
            if (state == START_BIT) begin
                // advance bit index after the START_BIT cycle completes
                bit_select <= bit_select + 1;
            end else if (state == IDLE && start) begin
                bit_select <= '0; // prepare for a fresh operation
            end
        end
    end

    // next-state logic
    always_comb begin
        next = state;
        start_bit = 1'b0;
        start_op_pulse = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    next = START_BIT;
                    start_op_pulse = 1'b1; // instruct lanes to latch operands
                    start_bit = 1'b1;      // also start bit 0 immediately this cycle
                end
            end

            START_BIT: begin
                // broadcast one-cycle start to lanes for current bit
                start_bit = 1'b1;
                next = WAIT_BIT;
            end

            WAIT_BIT: begin
                // wait for all lanes to finish this micro-step
                if (&lane_done) begin
                    if (bit_select == BIT_WIDTH - 1)
                        next = FINISHED;
                    else
                        next = START_BIT;
                end
            end

            FINISHED: begin
                // pulse done for one cycle; then return to IDLE
                next = IDLE;
            end
        endcase
    end

    assign done = (state == FINISHED);

    // ------------------------
    // SIMD lanes instantiation
    // ------------------------
    // We'll implement the lane as an internal module (simd_lane). Each lane:
    // - loads operands on start_op_pulse
    // - on each start_bit performs micro-step for bit 'bit_select'
    // - sets lane_done to indicate it finished this micro-step
    // - produces result when all bits are complete
    //
    // Note: arithmetic is unsigned. For SUB we compute A + (~B + 1) via invert and initial carry.

    for (genvar i = 0; i < LANES; i++) begin : lanes
        // Per-lane wires
        logic lane_done_w;
        logic [BIT_WIDTH-1:0] res_w;
        logic div0_w;

        simd_lane #(
            .BIT_WIDTH(BIT_WIDTH)
        ) lane_inst (
            .clk        (clk),
            .reset      (reset),
            .start_bit  (start_bit),
            .bit_select    (bit_select),
            .start_op   (start_op_pulse),

            .op_code         (op_code),

            .a_input       (a[i]),
            .b_input       (b[i]),

            .result_out (res_w),
            .done_bit   (lane_done_w),
            .div_by_zero(div0_w)
        );

        assign lane_done[i] = lane_done_w;
        assign result[i]    = res_w;
        assign div_by_zero[i] = div0_w;
    end

endmodule
