# Warp-Scheduled GPU

A small programmable GPU built in SystemVerilog and verified in simulation.
It executes a custom 32-bit instruction set across parallel lanes, with
round-robin warp scheduling to let ready warps run while others wait on memory.

The main demo renders Mandelbrot images at **16x16, 128x128, and 320x240**.
Every RGB pixel and iteration count is checked against both an independent
Python reference and a Python GPU interpreter.

## Design specifications

| Component | Design |
|---|---|
| Cores | 1 |
| Execution lanes | 8 in the demo; parameterized |
| Resident warps | 4 in the demo; parameterized |
| Resident thread contexts | 32 with the default configuration |
| Execution | Single-issue, in-order; one warp issues across the lanes |
| Scheduler | Round-robin among ready warps |
| Registers | 16 x 32-bit registers per lane per warp; r0 is always zero |
| Register storage | 2 KiB in the default 8-lane, 4-warp configuration |
| Warp state | Independent PC, active mask, and wait state per warp |
| Divergence | Predicated writes and an 8-entry mask stack per warp |
| Arithmetic | 32-bit integer/bitwise operations and signed Q16.16 multiplication |
| Instruction format | 32 bits: 6-bit opcode, three 4-bit register fields, 14-bit immediate; LUI uses an 18-bit payload |
| Instruction memory | Separate asynchronous ROM; 256 words by default |
| Data memory | Shared, aligned 32-bit RAM; 64 KiB by default, resized for demos |
| Memory arbitration | Round-robin, one external transaction in flight |
| Pending memory state | One memory-instruction context per resident warp/lane |
| Performance counters | Five 64-bit counters |

The lanes share fetch and decode, but have separate ALUs and register storage.
The four warps share the eight physical lanes; they do not represent 32 ALUs.
The ISA is custom and is **not RISC-V binary compatible**.

## Implemented features

- Arithmetic, logical operations, shifts, signed comparisons, MIN/MAX, and Q16.16 MUL.
- Constants, branches, aligned loads/stores, and warp completion.
- Lane/warp IDs, configuration values, and four launch arguments through RDSR.
- SETM, TMC, PUSHM, POPM, and BALLOT for masked execution.
- BARRIER synchronization and WSPAWN for launching inactive warp slots.
- Fault detection for invalid instructions, addresses, and mask-stack operations.
- Counters for cycles, accepted instructions, active lane-instructions,
  scheduler-idle cycles, and memory-blocked cycles.
- Python assembler with labels and hexadecimal program output.

## Run the demo

Requirements: **Python 3**, **Icarus Verilog** (`iverilog`), and **vvp**.
No FPGA board is required. Run commands from the repository root.

```sh
python3 tools/run_mandelbrot.py --resolution 16
python3 tools/run_mandelbrot.py --resolution 128
python3 tools/run_mandelbrot.py --resolution 320x240
```

Run and compare all three:

```sh
python3 tools/run_mandelbrot.py --resolution all
```

Results are generated under
`output/mandelbrot/<resolution>/seahorse_step0/`, including native-resolution
images, an enlarged preview, the RTL RAM dump, and verification metrics.
The runner also generates Markdown and CSV comparison reports. Output files
are generated locally and are ignored by Git unless explicitly added.
Large RTL simulations can take several minutes.

## Verified Mandelbrot results

All runs use 8 lanes, 4 warps, Q16.16 arithmetic, and a 128-iteration limit.
They use the same center and horizontal view; 320x240 preserves its 4:3 aspect
ratio and therefore covers a different vertical span.

| Resolution | Pixels | Simulated cycles | Cycles/pixel | Issued-lane utilization |
|---|---:|---:|---:|---:|
| 16x16 | 256 | 29,040 | 113.44 | 53.5% |
| 128x128 | 16,384 | 1,245,679 | 76.03 | 84.1% |
| 320x240 | 76,800 | 6,890,640 | 89.72 | 90.0% |

Issued-lane utilization is active lane-instructions divided by
(issued instructions x lanes). These are simulation measurements, not
measured FPGA clock rates or FPS.

## Assemble and test

```sh
python3 tools/assembler.py software/kernels/add.S -o output/programs/add.hex
python3 model/gpu_model.py output/programs/add.hex --launch-all -o output/model.json
python3 -m unittest discover -s tests -v
```

The Python suite includes comparisons against actual RTL execution, so it
also requires Icarus Verilog. SystemVerilog testbenches are in `sim/tb/`;
the Mandelbrot runner compiles and runs its end-to-end test automatically.

## Project layout

- `rtl/core/`: execution, scheduling, warp state, masks, synchronization, and counters.
- `rtl/memory/`: instruction ROM, data RAM, and memory arbiter.
- `rtl/gpu/`: integrated GPU top level.
- `software/kernels/`: assembly examples and Mandelbrot kernel template.
- `tools/`: assembler and demo runner.
- `model/`: GPU interpreter and independent Mandelbrot reference.
- `sim/tb/`: hardware testbenches.
- `tests/`: Python tests.
- `docs/`: ISA, memory interface, and demo documentation.

## Current scope

The project is verified in simulation. FPGA synthesis, timing closure, physical
board execution, VGA scanout, PRESENT/framebuffer swapping, and a serial host
interface have not been demonstrated. The displayed images are exported from
simulated RAM. LLM inference is not part of the verified GPU demo.
