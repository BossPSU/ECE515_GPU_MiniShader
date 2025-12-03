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

  word_t exp_result;

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

  function automatic word_t ref_model(
    word_t aa,
    word_t bb,
    opcodes_t op
  );
    case (op)
      OP_ADD:    return aa + bb;
      OP_SUB:    return aa - bb;
      OP_MUL:    return aa * bb;
      OP_DIV:    return (bb == 0) ? 32'hFFFFFFFF : (aa / bb);
      OP_MIN:    return (aa < bb) ? aa : bb;
      OP_MAX:    return (aa > bb) ? aa : bb;
      OP_AND:    return aa & bb;
      OP_OR:     return aa | bb;
      OP_XOR:    return aa ^ bb;
      OP_XNOR:   return ~(aa ^ bb);
      default:   return '0;
    endcase
  endfunction

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

  task automatic run_random_arithmetic_tests(int num_tests);
    for (int t = 0; t < num_tests; t=t+1) begin

      // Randomize inputs
      read_reg0 = $urandom();
      read_reg1 = $urandom();
      mem_read_data = $urandom();
      immd = $urandom();

      opcode = opcodes_t'($urandom_range(0, 10));  // valid ops only excluding LOAD/STORE, MATADD/MATMUL

      #1; // allow settle <-- Learned lesson the hard way last time! Need to account for delays

      exp_result = ref_model(read_reg0, read_reg1, opcode);
      if (reg_write_en && reg_write_data !== exp_result) begin
        $error("Random Test %0d: Mismatch for %s  A=%0d  B=%0d  expected=%0d got=%0d",
               t, opname(opcode), read_reg0, read_reg1, exp_result, reg_write_data);
        errors++;
      end
      else begin
        $display("Random Test %0d: Match for %s  A=%0d  B=%0d  expected=%0d got=%0d",
                 t, opname(opcode), read_reg0, read_reg1, exp_result, reg_write_data);
      end
    end
  endtask

  task automatic run_randomized_load_tests(int num_tests);
    for (int t = 0; t < num_tests; t=t+1) begin

      // Randomize inputs
      mem_read_data = $urandom();

      opcode = OP_LOAD;

      #1; // allow combinational settle

      // Check LOAD
      exp_result = mem_read_data;
      if (reg_write_en && reg_write_data !== exp_result) begin
        $error("LOAD Test %0d: Mismatch  mem_read_data=%0d  expected=%0d got=%0d",
               t, mem_read_data, exp_result, reg_write_data);
        errors++;
      end else begin
        $display("LOAD Test %0d: Match  mem_read_data=%0d  expected=%0d got=%0d",
                 t, mem_read_data, exp_result, reg_write_data);
      end
    end
  endtask

  task automatic run_randomized_store_tests(int num_tests);
    for (int t = 0; t < num_tests; t=t+1) begin

      // Randomize inputs
      read_reg0 = $urandom();
      immd = $urandom_range(0, 1024);

      opcode = OP_STORE;

      #1;

      // Check STORE
      if (!(mem_write_en &&
            mem_write_data === read_reg0 &&
            mem_write_addr === immd[$clog2(MEM_DEPTH)-1:0])) begin
        $error("STORE Test %0d: Mismatch  store_value=%0d  immd_addr=%0d  got_en=%b addr=%0d data=%0d",
               t, read_reg0, immd,
               mem_write_en, mem_write_addr, mem_write_data);
        errors++;
      end else begin
        $display("STORE Test %0d: Match  store_value=%0d  immd_addr=%0d",
                 t, read_reg0, immd);
      end
    end
  endtask

  initial begin
    // init
    errors = 0;
    checks = 0;

    $display("\n=== TB: ALU (verbose self-check) ===");
    #10;

    opcode = OP_NOP;
    run_random_arithmetic_tests(1000);
    #10;

    run_randomized_load_tests(1000);
    #10;

    run_randomized_store_tests(1000);
    #10;
    
    if (errors == 0) $display("\n*** ALU TB PASSED ***");
    else $display("\n*** ALU TB FAILED: %0d errors", errors);
   
    $finish;

  end
endmodule