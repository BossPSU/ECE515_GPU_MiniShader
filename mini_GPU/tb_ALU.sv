`timescale 1ns/1ps
import GPU_Shader_pkg::*;
import opcode_pkg::*;
module tb_ALU;
  // Clock (kept for uniformity)
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  // DUT ports
  word_t read_reg0, read_reg1, mem_read_data;
  opcodes_t opcode;
  logic [10:0] immd;

  // outputs
  logic        reg_write_en;
  int unsigned reg_write_idx;
  word_t       reg_write_data;
  logic        mem_write_en;
  logic [$clog2(MEM_DEPTH)-1:0] mem_write_addr;
  word_t       mem_write_data;

  // Instantiate DUT
  ALU dut (
    .read_reg0(read_reg0),
    .read_reg1(read_reg1),
    .mem_read_data(mem_read_data),
    .opcode(opcode),
    .immd(immd),
    .reg_write_en(reg_write_en),
    .reg_write_idx(reg_write_idx),
    .reg_write_data(reg_write_data),
    .mem_write_en(mem_write_en),
    .mem_write_addr(mem_write_addr),
    .mem_write_data(mem_write_data)
  );

  // helpers / counters (declared before any procedural statements)
  int errors;
  int checks;

  // opcode -> string helper
  function string opname(opcodes_t op);
    case (op)
      OP_NOP:    return "NOP";
      OP_ADD:    return "ADD";
      OP_SUB:    return "SUB";
      OP_MUL:    return "MUL";
      OP_DIV:    return "DIV";
      OP_MIN:    return "MIN";
      OP_MAX:    return "MAX";
      OP_AND:    return "AND";
      OP_OR:     return "OR";
      OP_XOR:    return "XOR";
      OP_XNOR:   return "XNOR";
      OP_LOAD:   return "LOAD";
      OP_STORE:  return "STORE";
      OP_MATADD: return "MATADD";
      OP_MATMUL: return "MATMUL";
      default:    return {"OP(", $sformatf("%0d", op), ")"};
    endcase
  endfunction

  initial begin
    // init
    errors = 0;
    checks = 0;

    $display("\n=== TB: ALU (verbose self-check) ===");

    // A small set of tests with printed context
    // Test vector list: {read_reg0, read_reg1, opcode, immd (for STORE/LOAD or unused), expected}
    // We'll handle expected in-line per-op
    // 1) ADD
    read_reg0 = 20; read_reg1 = 5; opcode = OP_ADD; immd = 0;
    #1;
    checks++;
    $display("Test %0d: %s  A=%0d  B=%0d", checks, opname(opcode), read_reg0, read_reg1);
    $display("  expected: 25");
    $display("  got     : %0d (reg_write_en=%b)", reg_write_data, reg_write_en);
    if (reg_write_en && reg_write_data == 25) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // 2) SUB
    read_reg0 = 20; read_reg1 = 5; opcode = OP_SUB;
    #1; checks++;
    $display("Test %0d: %s  A=%0d  B=%0d", checks, opname(opcode), read_reg0, read_reg1);
    $display("  expected: 15");
    $display("  got     : %0d (reg_write_en=%b)", reg_write_data, reg_write_en);
    if (reg_write_en && reg_write_data == 15) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // 3) MUL
    read_reg0 = 6; read_reg1 = 7; opcode = OP_MUL;
    #1; checks++;
    $display("Test %0d: %s  A=%0d  B=%0d", checks, opname(opcode), read_reg0, read_reg1);
    $display("  expected: 42");
    $display("  got     : %0d (reg_write_en=%b)", reg_write_data, reg_write_en);
    if (reg_write_en && reg_write_data == 42) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // 4) DIV
    read_reg0 = 100; read_reg1 = 4; opcode = OP_DIV;
    #1; checks++;
    $display("Test %0d: %s  A=%0d  B=%0d", checks, opname(opcode), read_reg0, read_reg1);
    $display("  expected: 25");
    $display("  got     : %0d", reg_write_data);
    if (reg_write_en && reg_write_data == 25) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // 5) DIV by zero (show sentinel)
    read_reg0 = 1; read_reg1 = 0; opcode = OP_DIV;
    #1; checks++;
    $display("Test %0d: %s  A=%0d  B=%0d (div0)", checks, opname(opcode), read_reg0, read_reg1);
    $display("  expected: sentinel (e.g. 0xFFFF_FFFF) or impl-defined");
    $display("  got     : 0x%08h", reg_write_data);
    $display("  (no strict pass/fail for div-by-zero)\n");

    // 6) AND/OR/XOR
    read_reg0 = 32'hF0F0_F0F0; read_reg1 = 32'h0F0F_0F0F; opcode = OP_AND;
    #1; checks++;
    $display("Test %0d: %s  A=0x%08h  B=0x%08h", checks, opname(opcode), read_reg0, read_reg1);
    $display("  expected: 0x%08h", (read_reg0 & read_reg1));
    $display("  got     : 0x%08h", reg_write_data);
    if (reg_write_en && reg_write_data == (read_reg0 & read_reg1)) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    opcode = OP_OR; #1; checks++;
    $display("Test %0d: %s", checks, opname(opcode));
    $display("  expected: 0x%08h", (read_reg0 | read_reg1));
    $display("  got     : 0x%08h", reg_write_data);
    if (reg_write_en && reg_write_data == (read_reg0 | read_reg1)) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    opcode = OP_XOR; #1; checks++;
    $display("Test %0d: %s", checks, opname(opcode));
    $display("  expected: 0x%08h", (read_reg0 ^ read_reg1));
    $display("  got     : 0x%08h", reg_write_data);
    if (reg_write_en && reg_write_data == (read_reg0 ^ read_reg1)) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // 7) LOAD: mem_read_data -> reg
    mem_read_data = 12345; opcode = OP_LOAD;
    #1; checks++;
    $display("Test %0d: %s  mem_read_data=%0d", checks, opname(opcode), mem_read_data);
    $display("  expected: 12345  got: %0d", reg_write_data);
    if (reg_write_en && reg_write_data == 12345) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // 8) STORE: expect mem_write outputs
    read_reg0 = 777; immd = 11; opcode = OP_STORE;
    #1; checks++;
    $display("Test %0d: %s  store_value=%0d  immd_addr=%0d", checks, opname(opcode), read_reg0, immd);
    $display("  got mem_write_en=%b addr=%0d data=%0d", mem_write_en, mem_write_addr, mem_write_data);
    if (mem_write_en && mem_write_data == 777 && mem_write_addr == immd[$clog2(MEM_DEPTH)-1:0]) $display("  PASS\n"); else begin $display("  FAIL\n"); errors++; end

    // Summary
    if (errors == 0) $display("\n*** ALU TB PASSED (%0d checks) ***", checks);
    else $display("\n*** ALU TB FAILED: %0d errors out of %0d checks ***", errors, checks);

    #10; $finish;
  end
endmodule
