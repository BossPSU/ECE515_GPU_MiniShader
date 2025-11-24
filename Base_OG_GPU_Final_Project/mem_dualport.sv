
// mem_dualport.sv
`timescale 1ns/1ps
import GPU_Shader_pkg::*;
module mem_dualport
  #(
    parameter int ADDR_WIDTH = $clog2(MEM_DEPTH)
  )
  (
    input  logic                   clk,
    // per-lane write (synchronous)
    input  logic [lanes-1:0]       write_en,
    input  logic [ADDR_WIDTH-1:0]  write_addr [lanes-1:0],
    input  word_t                  write_data [lanes-1:0],

    // per-lane read ports (combinational read-before-write model)
    input  logic [ADDR_WIDTH-1:0]  read_addr_a [lanes-1:0],
    output word_t                  read_data_a [lanes-1:0],
    input  logic [ADDR_WIDTH-1:0]  read_addr_b [lanes-1:0],
    output word_t                  read_data_b [lanes-1:0]
  );

  // memory array
  word_t mem [0:MEM_DEPTH-1];

  // combinational reads (read-before-write)
  always_comb begin
    for (int i = 0; i < lanes; i++) begin
      if (read_addr_a[i] < MEM_DEPTH) read_data_a[i] = mem[read_addr_a[i]];
      else read_data_a[i] = '0;
      if (read_addr_b[i] < MEM_DEPTH) read_data_b[i] = mem[read_addr_b[i]];
      else read_data_b[i] = '0;
    end
  end

  // synchronous writes - writes committed on clock edge
  always_ff @(posedge clk) begin
    for (int i = 0; i < lanes; i++) begin
      if (write_en[i]) begin
        if (write_addr[i] < MEM_DEPTH)
          mem[write_addr[i]] <= write_data[i];
      end
    end
  end

  // optional reset/init - simulator convenience (uncomment if needed)
  // initial begin for (int i=0;i<MEM_DEPTH;i++) mem[i]=0; end

endmodule
