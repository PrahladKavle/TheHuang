# Custom GPU ISA v0

This is a custom ISA, not RISC-V binary compatible. All instructions are 32 bits.
Normal layout: opcode [31:26], rd [25:22], rs1 [21:18], rs2 [17:14], immediate [13:0].
PCs and memory addresses are byte addresses. Instructions are 4-byte aligned.

- 0: ADD
- 1: SUB
- 2: AND
- 3: OR
- 4: XOR
- 5: SLT
- 6: MUL
- 7: SHL
- 8: SHR
- 9: SEQ
- 10: MIN
- 11: MAX
- 12: LDI
- 13: LUI
- 14: RDSR
- 15: SETM
- 16: PUSHM
- 17: POPM
- 18: TMC
- 19: BALLOT
- 20: BRANY
- 21: BR
- 22: RET
- 23: WSPAWN
- 24: BARRIER
- 25: LDR
- 26: STR
- 27: PRESENT

## Operand rules

Arithmetic uses rd, rs1, rs2. SHL/SHR instead use immediate[4:0].
SLT/MIN/MAX are signed. SHR is logical. MUL is signed Q16.16,
returning bits [47:16] of the signed 64-bit product, with wrapping overflow.
LDI writes zero-extended imm14. LUI writes {instruction[17:0],14'b0};
its 18-bit payload occupies rs2 and imm fields. Any 32-bit constant is
formed with LUI into one register, LDI into a temporary, then OR.
This payload exception is necessary: two 14-bit payloads cannot represent 32 bits.

LDR/STR use rs1 + sign-extended imm14 as byte address; STR data is rs2.
BR/BRANY targets are PC + 4 + (signed imm14 << 2).
WSPAWN uses the same PC-relative target; rs1 supplies a warp-bitmask.
RDSR uses unsigned imm14: 0=lane ID, 1=warp ID, 2=lane count,
3=resident warp capacity, 16..19=ARG0..ARG3. Other selectors fault.
Four arguments are captured per warp on launch via launch_args[0:3].
RDSR obeys the active mask and register-zero protection.
SETM uses rs1 predicates; TMC takes a uniform packed mask from lane 0 rs1.
BALLOT uses rs1 predicates among active lanes, broadcasting to active rd lanes.
PUSHM saves the current mask; POPM restores it. RET ends the warp.
Unused fields are ignored in v0.

## Integration status

The decoder emits requests, not completed side effects. Gate them on accepted issue.
use_immediate selects ALU operand B for shifts and load/store address calculation.
LDI/LUI require immediate-to-register writeback, bypassing the ALU.
MIN/MAX execute as signed comparisons using ALU controls 10/11.
Branch and special-register execution are integrated into minimal_core.
SETM, TMC, PUSHM and POPM are integrated. Each warp has an 8-entry
mask stack by default (MASK_STACK_DEPTH). SETM intersects the old mask with
per-lane rs1 != 0; TMC replaces it with the low LANES bits of lane 0 rs1.
TMC can re-enable lanes even from an empty mask; lane 0 rs1 must be initialized.
Mask control executes even when all lanes are inactive. PUSHM saves without
changing the mask; POPM restores. Stack underflow/overflow faults without
PC or mask changes. Launch resets that warp's stack. Supported lane counts
for packed TMC masks are 1..32. A partial launch mask is an initial mask,
not a permanent bound: software must preserve it when restoring/replacing masks.
BALLOT is integrated: bit i is active_mask[i] && (rs1[i] != 0),
zero-extended to 32 bits and written to rd of each active lane. Inactive lanes
retain rd, no active lanes means no writes, and rd may alias rs1.
BARRIER and WSPAWN are integrated for one block per core. The barrier snapshots
running warps at the first arrival; every participant must arrive at the same
logical barrier in program order or RET (retirement withdraws it). It releases
all arrivals after the last live member arrives, and resets for reuse. Even
zero-active-lane warps participate. Memory instructions complete before that
warp reaches its barrier. Software must avoid divergent barrier sequences;
there is no timeout for a live warp that never arrives.
No host launch or WSPAWN is permitted during an active barrier epoch: it faults.

WSPAWN reads a packed target-warp mask from lane 0 rs1 (initialized even if
lane 0 is inactive), and uses PC+4+(signed imm14<<2) for child entry. All targets
must be inactive; targeting the caller, running slots, non-existent slots, or
an out-of-ROM entry faults atomically. A zero target mask is a no-op. Launches
are serialized in increasing warp ID, pausing instruction issue briefly.
Children inherit the parent's active mask and four arguments; registers are
not copied or cleared. Each child's PC, waits and mask stack are initialized.
Host launches during spawn, or into running slots, fault. WARPS supports 1..32.
PRESENT execution remains pending. RET is not a RISC-V return instruction.
Instruction memory is asynchronous ROM; FPGA block-RAM inference may require
registered fetch later. No serial programming port is provided yet.
