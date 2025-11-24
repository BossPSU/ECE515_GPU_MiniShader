

//////////////////////////////////////////////////
// CAUTION
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!
// UNDER CONSTRUCTION DO NOT USE
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!
//////////////////////////////////////////////////










// `timescale 1ns/1ps
// import GPU_Shader_pkg::*;
// module tb_matmul;
//   logic clk;
//   logic rst_n;
//   initial clk = 0;
//   always #5 clk = ~clk;

//   localparam int AW = $clog2(MEM_DEPTH);

//   // shared mem
//   logic [lanes-1:0] mem_wen;
//   logic [AW-1:0]    mem_waddr [lanes-1:0];
//   word_t            mem_wdata [lanes-1:0];
//   logic [AW-1:0]    mem_raddr_a [lanes-1:0];
//   word_t            mem_rdata_a [lanes-1:0];
//   logic [AW-1:0]    mem_raddr_b [lanes-1:0];
//   word_t            mem_rdata_b [lanes-1:0];

//   mem_dualport #(.ADDR_WIDTH(AW)) mem0 (
//     .clk(clk),
//     .write_en(mem_wen),
//     .write_addr(mem_waddr),
//     .write_data(mem_wdata),
//     .read_addr_a(mem_raddr_a),
//     .read_data_a(mem_rdata_a),
//     .read_addr_b(mem_raddr_b),
//     .read_data_b(mem_rdata_b)
//   );

//   // engine signals
//   logic start, busy, done;
//   int unsigned M, K, N;
//   logic [31:0] baseA, baseB, baseC;

//   logic [$clog2(MEM_DEPTH)-1:0] eng_raddrA [lanes-1:0];
//   logic [$clog2(MEM_DEPTH)-1:0] eng_raddrB [lanes-1:0];
//   word_t eng_rdataA [lanes-1:0];
//   word_t eng_rdataB [lanes-1:0];
//   logic [lanes-1:0] eng_wen;
//   logic [$clog2(MEM_DEPTH)-1:0] eng_waddr [lanes-1:0];
//   word_t eng_wdata [lanes-1:0];

//   assign eng_rdataA = mem_rdata_a;
//   assign eng_rdataB = mem_rdata_b;
//   assign mem_raddr_a = eng_raddrA;
//   assign mem_raddr_b = eng_raddrB;
//   assign mem_wen = eng_wen;
//   assign mem_waddr = eng_waddr;
//   assign mem_wdata = eng_wdata;

//   MatrixMulEngine #(.LANES(lanes)) dut (
//     .clk(clk), .rst_n(rst_n), .start(start),
//     .M(M), .K(K), .N(N),
//     .baseA(baseA), .baseB(baseB), .baseC(baseC),
//     .busy(busy), .done(done),
//     .mem_raddrA(eng_raddrA), .mem_raddrB(eng_raddrB),
//     .mem_rdataA(mem_rdata_a), .mem_rdataB(mem_rdata_b),
//     .mem_wen(eng_wen), .mem_waddr(eng_waddr), .mem_wdata(eng_wdata)
//   );

//   // TB variables
//   int errors;
//   int i, r, c;
//   int timeout;
//   int waited;
//   int unsigned got;
//   int unsigned expected;

//   initial begin
//     errors = 0; timeout = 2000; waited = 0;
//     rst_n = 0; start = 0;
//     #20; rst_n = 1;

//     // 2x2 matrices
//     M = 2; K = 2; N = 2;
//     baseA = 10; baseB = 20; baseC = 30;

//     // preload A and B in row-major
//     mem0.mem[baseA + 0] = 1; mem0.mem[baseA + 1] = 2;
//     mem0.mem[baseA + 2] = 3; mem0.mem[baseA + 3] = 4;
//     mem0.mem[baseB + 0] = 5; mem0.mem[baseB + 1] = 6;
//     mem0.mem[baseB + 2] = 7; mem0.mem[baseB + 3] = 8;
//     // clear C
//     for (i=0; i < (M*N); i++) mem0.mem[baseC + i] = 0;

//     $display("\n=== TB: MatrixMulEngine (verbose 2x2) ===");
//     $display("  A (row-major):");
//     $display("    [%0d, %0d] [%0d, %0d]", mem0.mem[baseA+0], mem0.mem[baseA+1], mem0.mem[baseA+2], mem0.mem[baseA+3]);
//     $display("  B (row-major):");
//     $display("    [%0d, %0d] [%0d, %0d]", mem0.mem[baseB+0], mem0.mem[baseB+1], mem0.mem[baseB+2], mem0.mem[baseB+3]);

//     // start
//     #10; start = 1; #10; start = 0;

//     // wait for done
//     waited = 0;
//     while (!done && waited < timeout) begin @(posedge clk); waited++; end
//     if (!done) begin $display("ERROR: MatrixMulEngine timed out"); $finish; end
//     @(posedge clk); #1;

//     // expected C = [[19,22],[43,50]]
//     expected = 19; got = mem0.mem[baseC + 0];
//     $display("C[0,0]=%0d expected=%0d -> %s", got, expected, (got==expected) ? "PASS" : "FAIL"); if (got!=expected) errors++;
//     expected = 22; got = mem0.mem[baseC + 1];
//     $display("C[0,1]=%0d expected=%0d -> %s", got, expected, (got==expected) ? "PASS" : "FAIL"); if (got!=expected) errors++;
//     expected = 43; got = mem0.mem[baseC + 2];
//     $display("C[1,0]=%0d expected=%0d -> %s", got, expected, (got==expected) ? "PASS" : "FAIL"); if (got!=expected) errors++;
//     expected = 50; got = mem0.mem[baseC + 3];
//     $display("C[1,1]=%0d expected=%0d -> %s", got, expected, (got==expected) ? "PASS" : "FAIL"); if (got!=expected) errors++;

//     if (errors==0) $display("\n*** MatrixMulEngine TB PASSED ***"); else $display("\n*** MatrixMulEngine TB FAILED: %0d errors ***", errors);
//     #10; $finish;
//   end
// endmodule
