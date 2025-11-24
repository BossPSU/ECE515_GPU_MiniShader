`timescale 1ns/1ps
import GPU_Shader_pkg::*;
import opcode_pkg::*;

module tb_gpu_top;

  // ============================================================
  // CONSTANTS
  // ============================================================
  localparam int L = 4;
  localparam int NUMR = 64;
  localparam int REF_MEM_SIZE = 256;

  // ============================================================
  // DUT I/O
  // ============================================================
  logic clk;
  logic rst_n;
  logic start;

  GPU_Top #(.LANES(lanes), .IMEM_DEPTH(256)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start)
  );

  // clock gen
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // ============================================================
  // packer
  // ============================================================
  function automatic logic [31:0] pack_instr(
    opcodes_t opc, int d, int s0, int s1, int imm
  );
    return {opc, d[5:0], s0[5:0], s1[5:0], imm[7:0]};
  endfunction

  // ============================================================
  // Reference ALU
  // ============================================================
  function automatic logic [31:0] ref_alu(
    opcodes_t opc,
    logic [31:0] a,
    logic [31:0] b,
    logic [10:0] immd,
    logic [31:0] mem_read
  );
    case (opc)
      OP_ADD:  return a + b;
      OP_SUB:  return a - b;
      OP_MUL:  return a * b;
      OP_DIV:  return (b!=0) ? a/b : 32'hFFFF_FFFF;
      OP_MIN:  return (a<b)?a:b;
      OP_MAX:  return (a>b)?a:b;
      OP_AND:  return a & b;
      OP_OR:   return a | b;
      OP_XOR:  return a ^ b;
      OP_XNOR: return ~(a ^ b);
      OP_LOAD: return mem_read;
      default: return 32'h0;
    endcase
  endfunction

  // ============================================================
  // run program helper (start pulse + wait cycles)
  // ============================================================
  task automatic run_program(int n);
    int cyc = n*2 + 6;
    @(posedge clk) start = 1;
    @(posedge clk) start = 0;
    repeat(cyc) @(posedge clk);
    @(posedge clk);
  endtask

  // ============================================================
  // Scenario 1: SMOKE
  // ============================================================
  task automatic scenario_smoke();
    int i, l;
    logic [31:0] expected;
    logic [31:0] got;

    $display("=== SMOKE ===");

    for(i=0;i<16;i++) dut.scratchpad.mem[i] = 0;
    for(i=0;i<8;i++)  dut.scratchpad.mem[i] = i*2;

    for(l=0;l<L;l++) begin
      dut.regfile[l][0] = l+1;
      dut.regfile[l][1] = 10+l;
    end

    dut.imem[0] = pack_instr(OP_ADD ,2,0,1,0);
    dut.imem[1] = pack_instr(OP_LOAD,4,0,0,2);
    dut.imem[2] = pack_instr(OP_MUL ,5,2,4,0);
    dut.imem[3] = pack_instr(OP_STORE,0,5,0,16);

    run_program(4);

    // ----- enhanced debug output -----
    for(l=0;l<L;l++) begin
      expected = (l+1 + 10+l);
      got = dut.regfile[l][2];

      if(got !== expected) begin
        $display("ERR lane%0d r2  EXPECTED=%0d  GOT=%0d", l, expected, got);
      end else begin
        $display("OK  lane%0d r2  EXPECTED=%0d  GOT=%0d", l, expected, got);
      end
    end
  endtask

  // ============================================================
  // Scenario 2 (Edge Cases)
  // ============================================================
  task automatic scenario_edge();
    int l;
    logic [31:0] a_vals_arr [0:L-1];
    logic [31:0] b_vals_arr [0:L-1];
    logic [31:0] expected;
    logic [31:0] got;
    logic [31:0] a;
    logic [31:0] b;

    $display("=== EDGE ===");

    a_vals_arr[0]=0; b_vals_arr[0]=0;
    a_vals_arr[1]=0; b_vals_arr[1]=5;
    a_vals_arr[2]=32'hFFFF_FFFF; b_vals_arr[2]=1;
    a_vals_arr[3]=10; b_vals_arr[3]=3;

    for(l=0;l<L;l++) begin
      dut.regfile[l][0]=a_vals_arr[l];
      dut.regfile[l][1]=b_vals_arr[l];
    end

    dut.imem[0] = pack_instr(OP_DIV ,10,0,1,0);
    dut.imem[1] = pack_instr(OP_MIN ,11,0,1,0);
    dut.imem[2] = pack_instr(OP_MAX ,12,0,1,0);
    dut.imem[3] = pack_instr(OP_XNOR,13,0,1,0);

    run_program(4);

    // ----- enhanced debug -----
    for(l=0;l<L;l++) begin
      a = a_vals_arr[l];
      b = b_vals_arr[l];
      expected = (b!=0)? a/b : 32'hFFFF_FFFF;
      got      = dut.regfile[l][10];

      if(got !== expected) begin
        $display("DIV ERR lane%0d  EXPECTED=%h  GOT=%h", l, expected, got);
      end else begin
        $display("DIV OK  lane%0d  EXPECTED=%h  GOT=%h", l, expected, got);
      end
    end
  endtask

  // ============================================================
  // Scenario 3: MatrixAdd accelerator dispatch
  // ============================================================
  task automatic scenario_matadd();
    int i;
    int errors;
    int length;
    int baseA, baseB, baseC;
    int unsigned got;
    int unsigned expected;

    $display("\n=== ACCELERATOR: MATADD ===");

    // choose test parameters
    length = L + 2; // test length greater than lanes to ensure multiple engine bursts if implemented internally
    baseA = 16;
    baseB = 64;
    baseC = 128;

    // preload memory (use internal scratchpad reference)
    for (i = 0; i < length; i++) begin
      dut.scratchpad.mem[baseA + i] = i;
      dut.scratchpad.mem[baseB + i] = i * 5;
      dut.scratchpad.mem[baseC + i] = 32'hDEAD;
    end

    $display("  baseA=%0d baseB=%0d baseC=%0d length=%0d lanes=%0d", baseA, baseB, baseC, length, L);

    // Write control registers in lane 0 for engine args:
    // we follow the convention: src0->baseA index, src1->baseB index, dst->baseC index,
    // but the GPU_Top expects actual addresses in regfile[0][srcX], so we'll put addresses directly:
    // choose reg indices: use regfile[0][2] and regfile[0][3] for baseA/baseB, regfile[0][4] for baseC
    dut.regfile[0][2] = baseA; // cur_src0 will index this register
    dut.regfile[0][3] = baseB; // cur_src1 will index this register
    dut.regfile[0][4] = baseC; // cur_dst will index this register

    // place OP_MATADD instruction in IMEM[0] with fields:
    // dst = 4 (holds baseC), src0 = 2 (baseA), src1 = 3 (baseB), imm8 = length
    dut.imem[0] = pack_instr(OP_MATADD, 4, 2, 3, length);

    // run program (one instruction)
    run_program(1);

    // allow writes commit
    @(posedge clk); #1;

    // verify
    errors = 0;
    for (i = 0; i < length; i++) begin
      got = dut.scratchpad.mem[baseC + i];
      expected = dut.scratchpad.mem[baseA + i] + dut.scratchpad.mem[baseB + i];
      $display("  idx=%0d  A=%0d  B=%0d  -> C=%0d  expected=%0d", i, dut.scratchpad.mem[baseA + i], dut.scratchpad.mem[baseB + i], got, expected);
      if (got !== expected) begin
        $display("    FAIL idx=%0d", i); errors++;
      end else $display("    PASS idx=%0d", i);
    end

    if (errors == 0) $display("\n*** MatrixAddEngine TB PASSED ***");
    else $display("\n*** MatrixAddEngine TB FAILED: %0d errors ***", errors);
  endtask

  // ============================================================
  // MAIN
  // ============================================================
  initial begin
    rst_n=0; start=0;
    repeat(4) @(posedge clk);
    rst_n=1;

    // run tests
    scenario_smoke();
    scenario_edge();
    scenario_matadd();

    #50 $finish;
  end

endmodule
