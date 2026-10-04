# RV32I Processor

A small single-core RISC-V (RV32I subset) processor written in SystemVerilog.
It fetches instructions from an instruction SRAM, executes them, reads and
writes a separate data SRAM, and halts on `ebreak`. The repository also
includes a self-checking testbench and a Python reference model that produces
the expected results for each test program.

## Instruction Set

| Instruction | Operation |
|---|---|
| `add`, `sub` | Register-register add and subtract |
| `addi` | Add a sign-extended 12-bit immediate |
| `sll`, `srl` | Logical left and right shift by `rs2[4:0]` |
| `lw` | Load a word from data memory at `rs1 + imm` |
| `sw` | Store a word to data memory at `rs1 + imm` |
| `beq` | Branch to `pc + imm` if `rs1 == rs2` |
| `ebreak` | Halt the CPU |

Register `x0` is hardwired to zero.

## Architecture

The core is multi-cycle, not pipelined. Each instruction takes at least two
cycles because the SRAM macros have a one-cycle read latency.

- **Fetch** ([fetch.sv](src/verilog/cpu/fetch.sv)) holds the PC and picks the
  next one: the same PC on a stall, the branch target on a taken branch, or
  `pc + 4`. It sends the next PC to instruction SRAM so the instruction is
  ready on the following cycle.
- **Decode** ([decode.sv](src/verilog/cpu/decode.sv)) classifies the
  instruction, pulls out the register addresses, and builds the sign-extended
  I-, S- or B-type immediate.
- **Execute** ([execute.sv](src/verilog/cpu/execute.sv)) is a combinational
  ALU. It computes arithmetic and shift results, load/store addresses, and the
  branch condition and target.
- **Register file** ([reg_file.sv](src/verilog/cpu/reg_file.sv)) has 32
  registers with two read ports and one write port.
- **CPU top** ([cpu_top.sv](src/verilog/cpu/cpu_top.sv)) connects the stages.
  It chooses between the ALU result and loaded data for writeback, drives the
  data SRAM, stalls on loads, and raises `halted_o` on a valid `ebreak`.

### Load stalls

A load stalls the core until the data SRAM returns valid data. The SRAM's
ready signal stays high across back-to-back loads, so on its own it would
let a second load accept the first load's data. The core tracks when a new
instruction starts (the PC has changed since the previous cycle) and ignores
the ready signal on that first cycle, so every load waits for its own data.

### Memory system

- Two 1024 x 32 SRAMs (4 KB each), one for instructions and one for data,
  addressed by word.
- [memory_controller.sv](src/verilog/memory_controller.sv) gives the CPU
  access to both SRAMs while it runs. While the CPU is stopped, an external
  port can read and write them and read the register file. The testbench uses
  this port to load programs and check results.

External address map:

| Address | Target |
|---|---|
| `0x0000` | Instruction SRAM |
| `0x1000` | Data SRAM |
| `0x2000` | Register file (read-only) |

## Project Structure

```text
src/verilog/
  cpu/
    cpu_pkg.sv          Decoded instruction type enum
    cpu_top.sv          CPU integration, stalls, writeback, halt
    fetch.sv            PC and instruction fetch
    decode.sv           Instruction decode and immediate generation
    execute.sv          ALU and branch resolution
    reg_file.sv         32 x 32-bit register file
  chip_top.sv           CPU, SRAMs and memory controller
  memory_controller.sv  CPU / external-port arbitration
  sram_wrapper.sv       SRAM macro wrapper
  CF_SRAM_1024x32...v   1024 x 32 SRAM macro model
  tb_processor.sv       Full-processor testbench
  tb_fetch.sv           Fetch unit testbench
scripts/
  build_test.py         Assembles a test and generates expected outputs
  rv32_model.py         Python reference model
tests/<name>/           Test programs and expected results
sim/behav/              Xcelium simulation flow
```

## Verification

Each test directory holds an assembly program and its initial data memory.
`make generate` assembles the program and runs it on the Python reference
model to produce the expected final register file and data memory. The
testbench loads the program, runs the CPU until it halts, and compares both
against those expected results.

Tests:

- **One per instruction:** `add`, `addi`, `sub`, `sll`, `srl`, `lw`, `sw`,
  `branch_taken`, `branch_not_taken`, `ebreak`
- **Combined programs:** `complex1` and `complex2` mix loops, data-dependent
  branches and computed addresses

## Running

Requires Cadence Xcelium (`xrun`), SimVision and Python 3.

```sh
make help                 # list commands and available tests
make smoke                # check the build and testbench with a mock design
make test TEST=add        # run one test
make regress              # run every test and print a PASS/FAIL summary
make clean                # remove generated files
```

Options:

- `TEST=<name>` picks a directory under `tests/`.
- `MAX_CPU_CYCLES=<n>` sets how long the testbench waits for a halt (default 1000).
- `CROSSBAR_TIMEOUT=<n>` sets how long external-port accesses wait (default 20).

To view waveforms, run `make simvision` from `sim/behav/`.

To run the fetch unit testbench on its own, from `sim/behav/`:

```sh
make run_and_view INCLUDE_FILE_NAME=fetch.include TOP=tb_fetch
```

### Adding a test

1. Create `tests/<name>/program.asm` with the program, ending in `ebreak`.
2. Create `tests/<name>/data.hex` with the initial data memory, one 32-bit hex
   word per line starting at address `0x000`.
3. Run `make test TEST=<name>`. This generates the expected outputs and runs
   the simulation. `make regress` picks up the new test automatically.

New source files must be listed in `sim/behav/Include/cpu.include` before
`cpu_top.sv`.
