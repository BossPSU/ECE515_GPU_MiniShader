`timescale 1ns/1ps

module tb_simd_lockstep_alu;

    localparam int LANES = 4;
    localparam int WIDTH = 32;

    // Operation codes (same encoding as DUT)
    typedef enum logic [1:0] {
        OP_ADD = 2'd0,
        OP_SUB = 2'd1,
        OP_MUL = 2'd2,
        OP_DIV = 2'd3
    } opcode_t;

    // -------------------------
    // DUT I/O
    // -------------------------
    logic clk, rst;
    logic start;
    opcode_t op;

    logic [LANES-1:0][WIDTH-1:0] a, b;
    logic [LANES-1:0][WIDTH-1:0] result;
    logic [LANES-1:0] div_by_zero;
    logic done;

    // -------------------------
    // Instantiate the DUT
    // -------------------------
    simd_lockstep_alu #(
        .LANES(LANES),
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        .op(op),
        .a(a),
        .b(b),
        .result(result),
        .div_by_zero(div_by_zero)
    );

    // -------------------------
    // Clock Generation
    // -------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------
    // Reset task
    // -------------------------
    task automatic do_reset();
        rst = 1;
        start = 0;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
    endtask

    // ---------------------------------------------------------
    // Golden reference function
    // ---------------------------------------------------------
    function automatic logic [WIDTH-1:0] golden_calc(
        opcode_t op,
        logic [WIDTH-1:0] x,
        logic [WIDTH-1:0] y,
        output logic dbz
    );
        dbz = 0;

        case (op)
            OP_ADD: golden_calc = x + y;

            OP_SUB: golden_calc = x - y;

            OP_MUL: golden_calc = x * y; // truncated automatically to WIDTH bits

            OP_DIV: begin
                if (y == 0) begin
                    dbz = 1;
                    golden_calc = {WIDTH{1'b1}};  // match DUT behavior
                end else begin
                    golden_calc = x / y;
                end
            end

            default: golden_calc = '0;
        endcase
    endfunction

    // ---------------------------------------------------------
    // Task to run one test for a given opcode
    // ---------------------------------------------------------
    task automatic run_one_test(opcode_t opcode);
        logic [LANES-1:0][WIDTH-1:0] exp;
        logic [LANES-1:0] exp_dbz;

        // Randomize per-lane operands
        for (int i = 0; i < LANES; i++) begin
            a[i] = $urandom();
            b[i] = $urandom();
        end

        // Apply operation
        op = opcode;

        // Pulse start signal
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for DUT done
        @(posedge clk);
        wait (done);

        // Compute expected results
        for (int i = 0; i < LANES; i++) begin
            exp[i] = golden_calc(opcode, a[i], b[i], exp_dbz[i]);
        end

        // --------------------------------------
        // Compare results
        // --------------------------------------
        $display("\n--- Testing %s ---", opcode.name());
        for (int i = 0; i < LANES; i++) begin
            if (result[i] !== exp[i] || div_by_zero[i] !== exp_dbz[i]) begin
                $display("FAIL lane %0d:  A=%0d  B=%0d  EXP=%0d DBZ=%0b | GOT %0d DBZ=%0b",
                         i, a[i], b[i], exp[i], exp_dbz[i], result[i], div_by_zero[i]);
            end
            else begin
                $display("PASS lane %0d:  A=%0d  B=%0d -> %0d",
                         i, a[i], b[i], result[i]);
            end
        end
    endtask

    // ---------------------------------------------------------
    // Main randomized test sequence
    // ---------------------------------------------------------
    initial begin
        do_reset();

        repeat (8) run_one_test(OP_ADD);
        repeat (8) run_one_test(OP_SUB);
        repeat (8) run_one_test(OP_MUL);
        repeat (8) run_one_test(OP_DIV);

        $display("\nALL TESTS COMPLETED.\n");
        $finish;
    end

endmodule