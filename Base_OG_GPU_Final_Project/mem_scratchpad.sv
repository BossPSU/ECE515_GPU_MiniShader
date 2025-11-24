import GPU_Shader_pkg::*;

module mem_scratchpad #( parameter ADDR_WIDTH = $clog2(MEM_DEPTH) ) ( 
    input  logic                 clk,
    input  logic [lanes-1:0]     write_en,           // per-lane write enable
    input  logic [ADDR_WIDTH-1:0] write_addr [lanes-1:0],
    input  word_t                 write_data [lanes-1:0],
    input  logic [ADDR_WIDTH-1:0] read_addr  [lanes-1:0],
    output word_t                 read_data  [lanes-1:0]
);

  // actual memory array
  word_t mem [0:MEM_DEPTH-1];

  // combinational read (simple)
  always_comb begin
    for (int i = 0; i < lanes; i++) begin
      read_data[i] = mem[ read_addr[i] ];
    end
  end

  // synchronous write: any lane with write_en writes its data to its addr on rising edge
  // Note: concurrent writes to same address -> last writer (by index) will win in this simple model
  always_ff @(posedge clk) begin
    for (int i = 0; i < lanes; i++) begin
      if (write_en[i]) begin
        mem[ write_addr[i] ] <= write_data[i];
      end
    end
  end
endmodule
