````markdown
# Mini SIMD GPU Shader Core - SystemVerilog Reference Implementation

Welcome to the **Mini SIMD GPU Shader Core** reference project. This README provides a detailed walkthrough of the design, module-by-module explanations, execution flow, and developer guidance for extending or modifying the system.

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [High-Level Architecture](#high-level-architecture)
3. [Instruction Format](#instruction-format)
4. [Modules Walkthrough](#modules-walkthrough)
    - [opcode_pkg.sv](#opcode_pkgsv)
    - [GPU_Shader_pkg.sv](#gpu_shader_pkgsv)
    - [ALU.sv](#alusv)
    - [mem_dualport.sv](#mem_dualportsv)
    - [MatrixAddEngine.sv](#matrixaddenginesv)
    - [GPU_Top.sv](#gpu_topsv)
5. [Execution Flow Walkthrough](#execution-flow-walkthrough)
    - [Fetch-Decode-Execute](#fetch-decode-execute)
    - [MatrixAdd Accelerator Execution](#matrixadd-accelerator-execution)
6. [Testbenches and Verification](#testbenches-and-verification)
7. [Developer Guide](#developer-guide)
8. [ASCII Diagram: GPU_Top](#ascii-diagram-gpu_top)
9. [Future Enhancements](#future-enhancements)
10. [Acknowledgments](#acknowledgments)

---

## Project Overview
This project implements a **compact, educational SIMD GPU shader core** in SystemVerilog. Its main goals are:

- Teach and demonstrate GPU building blocks: lanes, SIMD register files, and scratchpad memory.
- Include small, self-contained accelerator engines (MatrixAdd, MatrixMul) with FSMs.
- Provide self-checking testbenches for immediate verification.
- Offer a modular, parameterizable design (lane count, memory depth, register file size) suitable for simulation-based exploration.

This reference implementation prioritizes **clarity and educational value** over high performance.

---

## High-Level Architecture
The GPU consists of:

- **Top controller (GPU_Top)**: orchestrates instruction fetch, decode, dispatch, and accelerator control.
- **SIMD lanes**: execute ALU instructions in lock-step.
- **Scratchpad memory**: dual-ported memory for per-lane reads/writes.
- **Accelerator engines**: handle multi-cycle operations like matrix addition and multiplication.

Each instruction is broadcast to all lanes, except for accelerator instructions, which assert a **start signal** to dedicated modules.

![High-level GPU Architecture](./images/arch_placeholder.png)

---

## Instruction Format
Each instruction is 32 bits:

| Bits      | Field           | Description                     |
|-----------|----------------|---------------------------------|
| 31:26     | Opcode          | Operation code                  |
| 25:21     | Destination Reg | Register to store result        |
| 20:16     | Source0 Reg     | First operand                   |
| 15:11     | Source1 Reg     | Second operand                  |
| 10:0      | Immediate       | Immediate value or offset       |

Instructions are decoded and broadcast to lanes for execution.

---

## Modules Walkthrough

### opcode_pkg.sv
Defines all opcodes for the GPU:

```verilog
typedef enum logic [5:0] {
    OP_NOP    = 6'd0,
    OP_ADD    = 6'd1,
    OP_SUB    = 6'd2,
    OP_MUL    = 6'd3,
    OP_DIV    = 6'd4,
    OP_MIN    = 6'd5,
    OP_MAX    = 6'd6,
    OP_AND    = 6'd7,
    OP_OR     = 6'd8,
    OP_XOR    = 6'd9,
    OP_XNOR   = 6'd10,
    OP_LOAD   = 6'd16,
    OP_STORE  = 6'd17,
    OP_MATADD = 6'd32,
    OP_MATMUL = 6'd33
} opcodes_t;
````

This package centralizes opcode definitions, ensuring consistency across modules and testbenches.

---

### GPU_Shader_pkg.sv

Defines key parameters and types:

```verilog
parameter int lanes     = 4;        // Number of SIMD lanes
parameter int MEM_DEPTH = 1024;     // Scratchpad depth (words)
parameter int NUM_REGS  = 64;       // Registers per lane
typedef logic [31:0] word_t;         // 32-bit word type
```

This package allows easy scaling of lane count, memory depth, and register file size.

---

### ALU.sv

The ALU executes arithmetic and logic operations:

```verilog
module ALU(
    input  word_t read_reg0,
    input  word_t read_reg1,
    input  word_t mem_read_data,
    input  opcodes_t opcode,
    input  logic [10:0] immd,
    output logic reg_write_en,
    output int unsigned reg_write_idx,
    output word_t reg_write_data,
    output logic mem_write_en,
    output logic [$clog2(MEM_DEPTH)-1:0] mem_write_addr,
    output word_t mem_write_data
);
```

**Functionality**:

* Arithmetic: ADD, SUB, MUL, DIV (division-by-zero handled with sentinel)
* Comparisons: MIN, MAX
* Bitwise: AND, OR, XOR, XNOR
* Memory: LOAD/STORE interface to scratchpad

---

### mem_dualport.sv

Per-lane dual-ported scratchpad memory:

```verilog
module mem_dualport #(
    parameter int ADDR_WIDTH = $clog2(MEM_DEPTH)
)(
    input logic clk,
    input logic [lanes-1:0] write_en,
    input logic [ADDR_WIDTH-1:0] write_addr [lanes-1:0],
    input word_t write_data [lanes-1:0],
    input logic [ADDR_WIDTH-1:0] read_addr_a [lanes-1:0],
    output word_t read_data_a [lanes-1:0],
    input logic [ADDR_WIDTH-1:0] read_addr_b [lanes-1:0],
    output word_t read_data_b [lanes-1:0]
);
```

* **Read-before-write semantics** ensures correct per-lane behavior.
* Synchronous writes commit on the rising clock edge.
* Supports two combinational read ports per lane.

---

### MatrixAddEngine.sv

Matrix addition accelerator:

```verilog
module MatrixAddEngine #(
    parameter int LANES = lanes
)(
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [31:0] baseA, baseB, baseC,
    input int unsigned length,
    output logic busy,
    output logic done,
    output logic [$clog2(MEM_DEPTH)-1:0] mem_raddrA [LANES-1:0],
    output logic [$clog2(MEM_DEPTH)-1:0] mem_raddrB [LANES-1:0],
    input  wire word_t mem_rdataA [LANES-1:0],
    input  wire word_t mem_rdataB [LANES-1:0],
    output logic [LANES-1:0] mem_wen,
    output logic [$clog2(MEM_DEPTH)-1:0] mem_waddr [LANES-1:0],
    output word_t mem_wdata [LANES-1:0]
);
```

**Key Features**:

* FSM-controlled batched reads/writes
* Supports multiple lanes at once
* Provides handshake signals: `start`, `busy`, `done`
* Performs element-wise addition `C[i] = A[i] + B[i]`

---

### GPU_Top.sv

Top-level controller connecting lanes and accelerators:

```verilog
module GPU_Top #(
    parameter int LANES = lanes,
    parameter int IMEM_DEPTH = 64
)(
    input logic clk,
    input logic rst_n,
    input logic start
);
```

**Responsibilities**:

* Fetch, decode, and dispatch instructions
* Broadcast ALU instructions to lanes
* Trigger accelerators and arbitrate memory access
* Maintain program counter and instruction memory

---

## Execution Flow Walkthrough

### Fetch-Decode-Execute

1. **Fetch** instruction from IMEM
2. **Decode** into opcode, dst, src0, src1, and immediate
3. **Dispatch**:

   * If regular ALU instruction → broadcast to lanes
   * If accelerator instruction → assert start, assign memory base addresses

### MatrixAdd Accelerator Execution

1. Lanes request input addresses from scratchpad
2. FSM computes `C[i] = A[i] + B[i]` for chunks up to `LANES` at a time
3. Writes results back to memory
4. Sets `done` when complete

---

## Testbenches and Verification

* **tb_ALU.sv**: checks arithmetic/logic ops
* **tb_mem_dualport.sv**: tests read-before-write and synchronous writes
* **tb_matadd.sv**: verifies matrix-add engine
* **tb_gpu_top.sv**: smoke test integrating everything, including a matrix-add scenario

Each testbench prints **PASS/FAIL** for each operation and reports final summary.

---

## Developer Guide

* **Scaling Lanes or Memory**: change `lanes`, `MEM_DEPTH`, or `NUM_REGS` in `GPU_Shader_pkg.sv`
* **Adding new ALU Ops**: extend `opcode_pkg.sv` and implement in `ALU.sv`
* **Adding Accelerators**: create module with start/busy/done signals and memory interfaces, update `GPU_Top.sv` to dispatch
* **Debugging**: use waveform dumps (`$dumpfile/$dumpvars`) and verbose console outputs in testbenches

---




## ASCII Diagram: GPU_Top


                       +-----------------------------+
                       |          GPU_Top            |
                       |-----------------------------|
                       |  PC Reg   Instr Decode      |
 start --->------------|  Fetch    Control Logic     |
 rst_n  -->------------|                             |
                       +--------------+--------------+
                                      |
                                      v
                       +--------------+--------------+
                       |             ALU             |
                       | (per-lane operations)       |
                       +--------------+--------------+
                                      |
                   +------------------+------------------+
                   |                                     |
                   v                                     v
        +--------------------+              +----------------------+
        |  Register File     |              |  MatrixAddEngine     |
        |  4×64 registers    |              |  Co-Processor        |
        +--------------------+              +----------------------+
                   |                                     |
                   +------------------+------------------+
                                      |
                                      v
                         +---------------------------+
                         |   mem_dualport.sv         |
                         |  Scratchpad Memory        |
                         +---------------------------+

* Arrows indicate **dataflow**.
* Lanes execute in **parallel**, accelerator uses FSM to control multiple elements per cycle.

---

## Future Enhancements

* Warp scheduler & per-lane PC for divergent execution
* Banked scratchpad memory with conflict detection
* Pipelined ALU & register file with hazard forwarding
* MatrixMul engine with tiling and FMA
* Simple assembler & loader for small kernels

---

## Acknowledgments

Thanks to all collaborators, reviewers, and the educational community for feedback improving this reference GPU core.

```
```
