// GPU_Shader_pkg.sv
package GPU_Shader_pkg;
  // Basic configuration - change these to scale the design
  parameter int lanes     = 4;        // number of SIMD lanes / "threads"
  parameter int MEM_DEPTH = 1024;     // scratchpad depth (words)
  parameter int NUM_REGS  = 64;       // registers per lane
  typedef logic [31:0] word_t;
endpackage
