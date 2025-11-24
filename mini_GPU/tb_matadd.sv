`timescale 1ns/1ps
import GPU_Shader_pkg::*;
module tb_matadd;
  logic clk;
  logic rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  localparam int AW = $clog2(MEM_DEPTH);

  // memory instantiation
  logic [lanes-1:0] mem_wen;
  logic [AW-1:0]    mem_waddr [lanes-1:0];
  word_t            mem_wdata [lanes-1:0];
  logic [AW-1:0]    mem_raddr_a [lanes-1:0];
  word_t            mem_rdata_a [lanes-1:0];
  logic [AW-1:0]    mem_raddr_b [lanes-1:0];
  word_t            mem_rdata_b [lanes-1:0];

  mem_dualport #(.ADDR_WIDTH(AW)) mem0 (
    .clk(clk),
    .write_en(mem_wen),
    .write_addr(mem_waddr),
    .write_data(mem_wdata),
    .read_addr_a(mem_raddr_a),
    .read_data_a(mem_rdata_a),
    .read_addr_b(mem_raddr_b),
    .read_data_b(mem_rdata_b)
  );

  // engine connections
  logic start, busy, done;
  logic [31:0] baseA, baseB, baseC;
  int unsigned length;

  logic [$clog2(MEM_DEPTH)-1:0] eng_raddrA [lanes-1:0];
  logic [$clog2(MEM_DEPTH)-1:0] eng_raddrB [lanes-1:0];
  word_t eng_rdataA [lanes-1:0];
  word_t eng_rdataB [lanes-1:0];
  logic [lanes-1:0] eng_wen;
  logic [$clog2(MEM_DEPTH)-1:0] eng_waddr [lanes-1:0];
  word_t eng_wdata [lanes-1:0];

  assign eng_rdataA = mem_rdata_a;
  assign eng_rdataB = mem_rdata_b;
  assign mem_raddr_a = eng_raddrA;
  assign mem_raddr_b = eng_raddrB;
  assign mem_wen = eng_wen;
  assign mem_waddr = eng_waddr;
  assign mem_wdata = eng_wdata;

  MatrixAddEngine #(.LANES(lanes)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .baseA(baseA), .baseB(baseB), .baseC(baseC), .length(length),
    .busy(busy), .done(done),
    .mem_raddrA(eng_raddrA), .mem_raddrB(eng_raddrB),
    .mem_rdataA(mem_rdata_a), .mem_rdataB(mem_rdata_b),
    .mem_wen(eng_wen), .mem_waddr(eng_waddr), .mem_wdata(eng_wdata)
  );

  // TB counters & helpers
  int errors;
  int i;
  int timeout;
  int waited;
  int unsigned got;
  int unsigned expected;

  initial begin
    errors = 0; timeout = 1000; waited = 0;
    rst_n = 0; start = 0;
    #20; rst_n = 1;

    // test setup
    length = lanes + 2;
    baseA = 16;
    baseB = 64;
    baseC = 128;

    // preload memory A and B
    for (i = 0; i < length; i++) begin
      mem0.mem[baseA + i] = i;
      mem0.mem[baseB + i] = i * 5;
      mem0.mem[baseC + i] = 32'hDEAD;
    end

    $display("\n=== TB: MatrixAddEngine (verbose) ===");
    $display("  baseA=%0d baseB=%0d baseC=%0d length=%0d lanes=%0d", baseA, baseB, baseC, length, lanes);

    // start engine
    #10; start = 1; #10; start = 0;

    // wait for done
    waited = 0;
    while (!done && waited < timeout) begin @(posedge clk); waited++; end
    if (!done) begin $display("ERROR: Engine timed out"); $finish; end

    // allow writes commit
    @(posedge clk); #1;

    // verify each element and print detailed info
    for (i = 0; i < length; i++) begin
      got = mem0.mem[baseC + i];
      expected = mem0.mem[baseA + i] + mem0.mem[baseB + i];
      $display("  idx=%0d  A=%0d  B=%0d  -> C=%0d  expected=%0d", i, mem0.mem[baseA + i], mem0.mem[baseB + i], got, expected);
      if (got !== expected) begin $display("    FAIL idx=%0d", i); errors++; end
      else $display("    PASS idx=%0d", i);
    end

    if (errors == 0) $display("\n*** MatrixAddEngine TB PASSED ***");
    else $display("\n*** MatrixAddEngine TB FAILED: %0d errors ***", errors);

    #10; $finish;
  end
endmodule
