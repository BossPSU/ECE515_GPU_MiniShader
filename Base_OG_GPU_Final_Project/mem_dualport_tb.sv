// mem_dualport_tb.sv
`timescale 1ns/1ps
module mem_dualport_tb;
  import GPU_Shader_pkg::*;

  // Clock
  logic clk;
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 10ns period
  end

  // Parameters from package
  localparam int AW = $clog2(MEM_DEPTH);

  // DUT signals (per-lane)
  logic [lanes-1:0]                     write_en;
  logic [AW-1:0]                        write_addr [lanes-1:0];
  word_t                                write_data [lanes-1:0];
  logic [AW-1:0]                        read_addr_a [lanes-1:0];
  word_t                                read_data_a [lanes-1:0];
  logic [AW-1:0]                        read_addr_b [lanes-1:0];
  word_t                                read_data_b [lanes-1:0];

  // Instantiate DUT
  mem_dualport #(.ADDR_WIDTH(AW)) dut (
    .clk(clk),
    .write_en(write_en),
    .write_addr(write_addr),
    .write_data(write_data),
    .read_addr_a(read_addr_a),
    .read_data_a(read_data_a),
    .read_addr_b(read_addr_b),
    .read_data_b(read_data_b)
  );

  // Test stimulus
  initial begin
    // Initialize
    for (int i = 0; i < lanes; i++) begin
      write_en[i] = 0;
      write_addr[i] = '0;
      write_data[i] = '0;
      read_addr_a[i] = '0;
      read_addr_b[i] = '0;
    end

    // Small test plan:
    // 1) Write some values to distinct addresses in cycles 1..N (using different lanes)
    // 2) On same cycle try to read those addresses -> should observe OLD value (read-before-write)
    // 3) Next cycle read the same addresses -> should observe NEW value

    #10; // wait for stable
    $display("\n--- mem_dualport: write/read behavior test ---");

    // Prepare test vectors
    int num_tests = lanes; // we'll issue up to 'lanes' writes at once
    int write_base = 4;
    for (int i = 0; i < num_tests; i++) begin
      // set writes that will happen on the next posedge
      write_en[i]    = 1'b1;
      write_addr[i]  = write_base + i;
      write_data[i]  = 100 + i; // distinct values
      // set read ports to the same addresses in same cycle -> expect old mem contents (initially zero)
      read_addr_a[i] = write_base + i;
      read_addr_b[i] = write_base + i;
    end

    // Snapshot combinational read outputs now (before posedge)
    #1;
    $display("Cycle %0d: reads before write commit (expect old values = 0)", $time);
    for (int i = 0; i < num_tests; i++) $display(" lane %0d read_a=%0d read_b=%0d (expected 0)", i, read_data_a[i], read_data_b[i]);

    // Now tick the clock to commit the writes
    @(posedge clk);
    // deassert write_en after posedge (we wrote values)
    for (int i = 0; i < num_tests; i++) write_en[i] = 0;

    // Immediately after posedge, combinational reads reflect new memory contents
    #1;
    $display("Cycle %0d: reads after write commit (expect new values 100..)", $time);
    int errors = 0;
    for (int i = 0; i < num_tests; i++) begin
      $display(" lane %0d read_a=%0d read_b=%0d (expected %0d)", i, read_data_a[i], read_data_b[i], 100 + i);
      if (read_data_a[i] !== (100 + i) || read_data_b[i] !== (100 + i)) errors++;
    end

    // Additional check: simultaneous writes to the same address (ambiguous behavior)
    // We'll write address X from multiple lanes in the same cycle and observe final value.
    int conflict_addr = write_base + 1;
    $display("\n--- mem_dualport: simultaneous write conflict test (note: undefined resolution) ---");
    // Prepare two lanes to write to same addr with different values
    write_en[0] = 1; write_addr[0] = conflict_addr; write_data[0] = 555;
    if (lanes > 1) begin
      write_en[1] = 1; write_addr[1] = conflict_addr; write_data[1] = 999;
    end

    // read from the address in same cycle (expect old value)
    read_addr_a[0] = conflict_addr;
    read_addr_b[0] = conflict_addr;
    #1; $display(" before commit read_a=%0d (expected old %0d)", read_data_a[0], 100+1);
    @(posedge clk);
    // deassert writes
    for (int i = 0; i < lanes; i++) write_en[i] = 0;
    #1;
    $display(" after commit read_a=%0d (one of written values expected)", read_data_a[0]);

    $display("\nSummary: mem_dualport test %0s", (errors==0) ? "PASSED" : "FAILED");

    #20;
    $finish;
  end

endmodule
