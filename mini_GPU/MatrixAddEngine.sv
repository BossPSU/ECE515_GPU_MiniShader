`timescale 1ns/1ps
import GPU_Shader_pkg::*;

module MatrixAddEngine
  #(
    parameter int LANES = lanes
  )
  (
    input  logic            clk,
    input  logic            rst_n,
    input  logic            start,           // pulse to start
    input  logic [31:0]     baseA, baseB, baseC, // word addresses (indices)
    input  int unsigned     length,          // number of elements
    output logic            busy,
    output logic            done,

    // memory ports (per-lane)
    output logic [$clog2(MEM_DEPTH)-1:0] mem_raddrA [LANES-1:0],
    output logic [$clog2(MEM_DEPTH)-1:0] mem_raddrB [LANES-1:0],
    input  wire     word_t                 mem_rdataA [LANES-1:0],
    input  wire     word_t                 mem_rdataB [LANES-1:0],
    output logic [LANES-1:0]               mem_wen,  // write enable per lane
    output logic [$clog2(MEM_DEPTH)-1:0]   mem_waddr [LANES-1:0],
    output word_t                          mem_wdata [LANES-1:0]
  );

  typedef enum logic [1:0] {S_IDLE=2'd0, S_RUN=2'd1, S_DONE=2'd2} state_t;
  state_t state;
  int unsigned idx; // element index (start of current chunk)
  logic [$clog2(MEM_DEPTH)-1:0] baseA_a, baseB_a, baseC_a;

  // safe conversion of bases
  always_comb begin
    baseA_a = baseA[$clog2(MEM_DEPTH)-1:0];
    baseB_a = baseB[$clog2(MEM_DEPTH)-1:0];
    baseC_a = baseC[$clog2(MEM_DEPTH)-1:0];
  end

  // FSM: issue chunks of LANES elements per cycle
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      idx <= 0;
      busy <= 1'b0;
      done <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          done <= 1'b0;
          busy <= 1'b0;
          if (start) begin
            idx <= 0;
            busy <= 1'b1;
            state <= S_RUN;
          end
        end
        S_RUN: begin
          // issue current chunk (idx). After issuing, advance idx.
          // If the next idx goes beyond length, move to DONE (but allow this cycle's writes to commit).
          if (idx + LANES >= length) begin
            idx <= idx + LANES; // move beyond length (will stop)
            state <= S_DONE;
          end else begin
            idx <= idx + LANES;
            // remain in S_RUN
          end
        end
        S_DONE: begin
          busy <= 1'b0;
          done <= 1'b1;
          if (!start) state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end

  // generate per-lane addresses and compute sums combinationally using 'idx'
  always_comb begin
    // defaults
    for (int i = 0; i < LANES; i++) begin
      mem_raddrA[i] = '0;
      mem_raddrB[i] = '0;
      mem_waddr[i]  = '0;
      mem_wen[i]    = 1'b0;
      mem_wdata[i]  = '0;
    end

    // For the chunk starting at 'idx' (which is the current chunk start this cycle)
    // compute per-lane element indices and outputs.
    for (int i = 0; i < LANES; i++) begin
      automatic int unsigned elem_idx; // declare automatic local, then assign
      elem_idx = idx + i;

      mem_raddrA[i] = baseA_a + elem_idx;
      mem_raddrB[i] = baseB_a + elem_idx;
      mem_waddr[i]  = baseC_a + elem_idx;
      // valid write enable only while running and within bounds
      mem_wen[i]    = (state == S_RUN) && (elem_idx < length);
      // data to write is sum (reads are combinational)
      mem_wdata[i]  = mem_rdataA[i] + mem_rdataB[i];
    end
  end

endmodule
