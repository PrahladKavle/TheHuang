# Assembler quick start

From the Gpu folder:

```sh
python3 tools/assembler.py software/kernels/add.S -o output/programs/add.hex
python3 -m unittest discover -s tests -v
```

Hex output has one 32-bit word per line, usable as PROGRAM_INIT_FILE.
Registers are r0..r15. Instructions and special-register names ignore case;
labels are case-sensitive. Commas separate operands. #, ; and // start comments.
Labels denote byte addresses; BR/BRANY/WSPAWN label offsets are calculated
relative to PC+4. A numeric branch operand is a signed instruction offset.

Examples:

```asm
RDSR r1, LANE_ID
SHL r2, r1, 2
STR r1, 0(r2)
LDR r3, 0(r2)
RET
```

Use `LI rDestination, constant, rScratch` for arbitrary 32-bit constants.
It always emits LUI, LDI, OR and overwrites scratch; both registers must be
nonzero and distinct. LUI itself takes an unsigned 18-bit upper payload;
LDI takes an unsigned 14-bit value. Memory offsets are signed byte offsets.
`.word` emits one raw unsigned 32-bit value. Expressions, macros and external
symbols are not supported yet. PRESENT assembles but execution still faults
until presentation hardware exists. An empty source emits an empty hex file.
