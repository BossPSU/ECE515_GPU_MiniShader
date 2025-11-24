`timescale 1ns/1ps
module MatrixMulEngine #(
    parameter int N = 4,               // Matrix dimension
    parameter int DATA_W = 32,         // Width of each matrix element
    parameter int LANES = 4            // Number of parallel compute lanes
)(
    input  logic                 clk,
    input  logic                 rst,

    // Start signal
    input  logic                 start,

    // Input matrices (row-major)
    input  logic [DATA_W-1:0]    A [0:N-1][0:N-1],
    input  logic [DATA_W-1:0]    B [0:N-1][0:N-1],

    // Output matrix (row-major)
    output logic [DATA_W-1:0]    C [0:N-1][0:N-1],

    // Done
    output logic                 done
);

    // =========================================================================
    // State machine
    // =========================================================================
    typedef enum logic [1:0] { IDLE = 2'd0, BUSY = 2'd1, DONE_ST = 2'd2 } state_t;
    state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // =========================================================================
    // Output counter: how many elements have been issued/produced so far (flattened)
    // =========================================================================
    localparam int TOT = N * N;
    // width to hold TOT
    localparam int CNT_W = $clog2(TOT + 1);

    logic [CNT_W-1:0] output_count;
    logic [CNT_W-1:0] next_output_count;

    // advance by PER_CYCLE elements each cycle while busy
    localparam int PER_CYCLE = LANES;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) output_count <= '0;
        else if (state == BUSY) output_count <= next_output_count;
        else if (state == IDLE) output_count <= '0;
    end

    // compute next count safely (saturate at TOT)
    always_comb begin
        if (output_count + PER_CYCLE >= TOT)
            next_output_count = TOT;
        else
            next_output_count = output_count + PER_CYCLE;
    end

    // =========================================================================
    // Next-state logic
    // =========================================================================
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) next_state = BUSY;
            end
            BUSY: begin
                if (output_count == TOT) next_state = DONE_ST;
            end
            DONE_ST: begin
                if (!start) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // Per-lane compute: each lane computes the dot product for one flattened index
    // Each lane is given a flattened index = output_count + lane_offset
    // =========================================================================
    logic [DATA_W-1:0] lane_result [0:LANES-1];

    genvar li;
    generate
        for (li = 0; li < LANES; li++) begin : LANE_GEN
            // Flattened index for this lane (combinational)
            // Use a local combinational variable to avoid width/auto issues
            logic [CNT_W-1:0] lane_flat_idx;
            always_comb lane_flat_idx = output_count + li;

            // compute row / col from flattened index (combinational)
            logic [$clog2(N)-1:0] row, col;
            always_comb begin
                if (lane_flat_idx < TOT) begin
                    row = lane_flat_idx / N;
                    col = lane_flat_idx % N;
                end else begin
                    row = '0;
                    col = '0;
                end
            end

            // Compute dot product combinationally into an accumulator of larger width
            // Use wider accumulator to avoid overflow for multiplications
            logic signed [DATA_W*2-1:0] acc;
            integer k;
            always_comb begin
                acc = '0;
                if (lane_flat_idx < TOT) begin
                    for (k = 0; k < N; k++) begin
                        // cast to signed extended for multiply-add — keep it simple (assume unsigned/positive)
                        acc = acc + $signed({1'b0, A[row][k]}) * $signed({1'b0, B[k][col]});
                    end
                end
            end

            // register the result to align with writeback timing
            always_ff @(posedge clk or posedge rst) begin
                if (rst) lane_result[li] <= '0;
                else if (state == BUSY) lane_result[li] <= acc[DATA_W-1:0];
            end
        end
    endgenerate

    // =========================================================================
    // Write lane results into C (synchronously)
    // =========================================================================
    integer w;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (w = 0; w < N; w = w + 1) begin
                for (int z = 0; z < N; z = z + 1) begin
                    C[w][z] <= '0;
                end
            end
        end else if (state == BUSY) begin
            // On each cycle write up to LANES results (if indices valid)
            for (w = 0; w < LANES; w = w + 1) begin
                automatic int flat = output_count + w;
                if (flat < TOT) begin
                    automatic int r = flat / N;
                    automatic int c = flat % N;
                    C[r][c] <= lane_result[w];
                end
            end
        end
    end

    assign done = (state == DONE_ST);

endmodule
