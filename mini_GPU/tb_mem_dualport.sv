`timescale 1ns/1ps
import GPU_Shader_pkg::*;
module tb_mem_dualport;
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  localparam int AW = $clog2(MEM_DEPTH);

  // DUT signals
  logic [lanes-1:0] write_en;
  logic [AW-1:0] write_addr [lanes-1:0];
  word_t write_data [lanes-1:0];
  logic [AW-1:0] read_addr_a [lanes-1:0];
  word_t read_data_a [lanes-1:0];
  logic [AW-1:0] read_addr_b [lanes-1:0];
  word_t read_data_b [lanes-1:0];

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

  // counters
  int i;
  int checks;
  int errors;

  initial begin
    checks = 0; errors = 0;

    // init
    for (i = 0; i < lanes; i++) begin
      write_en[i] = 0; write_addr[i] = '0; write_data[i] = '0;
      read_addr_a[i] = '0; read_addr_b[i] = '0;
    end

    $display("\n=== TB: mem_dualport (verbose) ===");

    // write unique values from each lane into distinct addresses
    for (i = 0; i < lanes; i++) begin
      write_en[i] = 1'b1;
      write_addr[i] = i + 8;
      write_data[i] = 32'h200 + i;
      read_addr_a[i] = i + 8;
      read_addr_b[i] = i + 8;
      $display("  lane %0d -> write_en=1 addr=%0d data=0x%08h", i, write_addr[i], write_data[i]);
    end
    #1;
    $display("  (Combinational read-before-write snapshot)");
    for (i = 0; i < lanes; i++) $display("    lane %0d read_a=0x%08h read_b=0x%08h", i, read_data_a[i], read_data_b[i]);
    @(posedge clk); // commit writes
    for (i = 0; i < lanes; i++) write_en[i] = 1'b0;
    #1;

    // verify
    for (i = 0; i < lanes; i++) begin
      checks++;
      $display("  Verify lane %0d: expected 0x%08h  got read_data_a=0x%08h", i, (32'h200 + i), read_data_a[i]);
      if (read_data_a[i] !== (32'h200 + i)) begin
        $display("    FAIL lane %0d", i); errors++;
      end else $display("    PASS lane %0d", i);
    end

    // test RAW (write and read same addr from two lanes)
    if (lanes >= 2) begin
      $display("\n  RAW test: two lanes write same address 0x%0d", 20);
      write_en[0] = 1; write_addr[0] = 20; write_data[0] = 32'hAAAA_AAAA;
      write_en[1] = 1; write_addr[1] = 20; write_data[1] = 32'hBBBB_BBBB;
      read_addr_a[0] = 20;
      #1;
      $display("    before commit read_data_a[0]=0x%08h (read-before-write)", read_data_a[0]);
      @(posedge clk);
      #1;
      $display("    after commit read_data_a[0]=0x%08h (one of the written values)", read_data_a[0]);
      // ambiguous which one wins - just informative
      write_en[0] = 0; write_en[1] = 0;
    end

    if (errors == 0) $display("\n*** mem_dualport TB PASSED (%0d checks) ***", checks);
    else $display("\n*** mem_dualport TB FAILED: %0d errors out of %0d checks ***", errors, checks);

    #10; $finish;
  end
endmodule
