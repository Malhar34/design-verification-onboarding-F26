# Fall 2026 DV Onboarding Test Plan

<!--
Make two copies of this template:
  1. testplan_initial.md, submitted before implementing tests.
  2. testplan_final.md, updated after implementation and coverage closure.

Keep the initial copy unchanged after review. HTML comments are editing
instructions and disappear from rendered Markdown.
-->

## Document information

| Field | Value |
| --- | --- |
| Verification engineer | Malhar Rathod, malharr123, mrathod34 |
| Plan revision | Final |
| Date | 2026-10-05 |

## Revision history

| Revision | Date | Changes |
| --- | --- | --- |
| Initial | 2026-09-26 | Initial planned tests |
| Final | 2026-10-05 | Implemented the driver, monitor, scoreboard, constraints, directed tests and assertions. Tests 1.3 to 1.27 were implemented as planned, except 1.13 (withdrawn), 1.20 and 1.23 (partly covered), and 1.24 and 1.25 (not implemented). |
| Final | 2026-10-05 | Review feedback on the initial plan was added: tests 1.28, 1.29 and 1.30, and the assertion `RESET_QUIESCES_CONTROL`. See the next section. |
| Final | 2026-10-05 | Monitor `observe_external_read` treated a leftover `rready` as the response to a new read, so `dmem[0x001]` returned the value of `dmem[0x000]`. Fixed by recording the request and checking `rready` on a later cycle. |
| Final | 2026-10-05 | Monitor `observe_cpu_memory` did not report CPU loads and stores once `dsram_en` dropped. Fixed by keeping the pending operation and reporting it on the next cycle. |
| Final | 2026-10-05 | Scoreboard `CPU_STORE` did not update `expected_dmem`, so a later readback compared against old data (random_5, seed 642649788, word 9). Fixed. |
| Final | 2026-10-05 | Driver `xbar_read` took a leftover `rready` as the response to a new SRAM read (random_19: `imem[0x266]` returned the data of the write before it). Fixed by waiting one cycle for SRAM windows. |
| Final | 2026-10-05 | The random test only wrote programs into memory and never ran the CPU, so the encrypted CPU passed. Replaced with a loop of 20 programs with reset, `init_memories()`, a timed run and readback. |
| Final | 2026-10-05 | `c_imm_range` corner weights applied to every instruction, so random programs were mostly `addi` with almost no branches. The weights now apply only to `addi`. |
| Final | 2026-10-05 | `c_mem_align` only limits the immediate. The version that uses register state was not implemented because I could not pull the updated scaffold (`git fetch` returned a 403 error). |
| Final | 2026-10-05 | `NO_MEM_ACCESS_WHEN_IDLE` first fired on every external data-memory access, because the memory controller raises `dsram_en` for the external port while `cpu_active` is low. It now ignores cycles where `r_en` or `w_en` is high. |
| Final | 2026-10-05 | `NO_STORE_TO_DATA0` was withdrawn. `init_memories()` fills data word 0 with a random value, and random program 13 stored to word 0 with 0 scoreboard mismatches (`evidence_NO_STORE_TO_DATA0.log`). `HALT_RELEASES_CPU` was added in its place. |

---

## Feedback from the review of the initial plan

| Feedback | What I did | Where |
| --- | --- | --- |
| Add a test for reset during CPU active | Test 1.28 `reset_while_active` | Section 1 |
| Add a test for external halt request | Test 1.29 `external_halt_loop` | Section 1 |
| Add a test for external memory boundaries in SRAM | Test 1.30 `ext_mem_boundaries` | Section 1 |
| Add an assertion for observing the control signals when reset is asserted | Assertion `RESET_QUIESCES_CONTROL` | Section 3 |

---

## Verification strategy

The testbench only uses what can be seen at the chip boundary: the external memory port (instruction SRAM, data SRAM and the read-only register window), the `cpu_halted` pulse, `cpu_active`, and the data-SRAM signals (`dsram_en`, `dsram_write_en`, `dsram_addr`, `dsram_wdata`, `dsram_rdata`). Nothing in this plan refers to CPU internals.

Two ideas shaped the plan.

**Checking the final state is not enough.** Reading registers and memory after the halt shows where the CPU ended up, not how it got there. The monitor rebuilds every CPU load and store from the data-SRAM signals, so the scoreboard checks the order of stores as well as the final memory.

**Tests are chosen by failure mode, not by opcode.** One easy example per instruction would pass on a CPU with a wrong sign extension, shift mask or address scaling. Each test below says which wrong implementation it is meant to catch.

| Group | Tests | Failure modes targeted |
| --- | --- | --- |
| Value classes and limits | 1.1, 1.5 to 1.9 | sign extension, wraparound, shift-amount masking, logical vs arithmetic shift |
| Register invariants | 1.3, 1.4, 1.15 | x0 always reads 0 and ignores writes |
| Adjacent-instruction dependencies | 1.2, 1.26, 1.27 | a result is not ready for the next instruction |
| Address translation | 1.10 to 1.12 | byte-to-word scaling, negative offsets |
| Field aliasing | 1.14 | store immediate bits treated as a destination register |
| Control flow | 1.16 to 1.19 | branch direction, backward targets, equality |
| Termination | 1.20 to 1.22 | halt behavior, unsupported encodings |
| Ownership and port protocol | 1.23 to 1.25 | memory handoff, read-only window, unmapped window |
| Added after review | 1.28 to 1.30 | reset during a run, external halt, SRAM boundaries |
| Withdrawn | 1.13 | `data[0]` is not required to stay 0 in this testbench |

---

## Open questions

| # | Question | Answer |
| --- | --- | --- |
| 1 | Does `asm_instr` take a byte or word offset for `OP_BEQ`? | Resolved 2026-09-26. A byte offset. `encode()` in `cpu_seq_item.svh` uses the standard B-type layout. |
| 2 | What does `OP_NOP` encode to? | Resolved 2026-09-26. `32'h0000_0000`, which matches no supported instruction. Test 1.22 uses it. |
| 3 | What does the port do for an external access with `addr[13:12] == 2'b11`? | Not answered. The README does not say. Test 1.25 was not implemented. |
| 4 | What happens to an external write made while `cpu_active` is high? | Not answered. The README only says the port is serviced while the CPU is disabled. Test 1.23 covers the normal flow only. |

---

# 1. Functional tests

## Functional-test summary

| Test ID | Test name | Functionality being tested | Expected result | Status |
| --- | --- | --- | --- | --- |
| 1.1 | `addi_imm_limits` | I-type immediate sign extension across its full range | Positive max, negative max, −1, and 0 all produce correct 32-bit values | Implemented (3 of 5 values), passed |
| 1.2 | `raw_dependency_chain` | A register written by instruction N is visible to instruction N+1 | Each result reflects the immediately preceding write | Implemented, passed |
| 1.3 | `x0_write_protection` | Writes targeting x0 are discarded | x0 reads 0 after both an `addi` and an `add` target it | Implemented, passed |
| 1.4 | `x0_source_reads_zero` | x0 reads as zero regardless of attempted writes | Arithmetic using x0 as a source behaves as if it were 0 | Implemented, passed |
| 1.5 | `add_value_classes` | Register-register add including 32-bit wraparound | Positive, mixed-sign, and overflow-wrap cases correct | Implemented, passed |
| 1.6 | `sub_value_classes` | Subtraction producing positive, negative, and zero results | Negative result is correct two's complement. Self subtract is 0 | Implemented, passed |
| 1.7 | `sll_shift_amount_masking` | Shift amount uses only the low 5 bits of rs2 | Shifts of 0, 31, 32, and 33 behave as 0, 31, 0, and 1 | Implemented, passed |
| 1.8 | `srl_is_logical` | Right shift fills with zeros, not the sign bit | 0x80000000 >> 1 yields 0x40000000, not 0xC0000000 | Implemented, passed |
| 1.9 | `shift_by_computed_amount` | Shift amount comes from a register, not an immediate | Shift by a runtime-computed value is correct | Implemented, passed |
| 1.10 | `sw_lw_roundtrip_distinct_words` | Stores and loads reach distinct memory words | Two values stored at different addresses read back independently | Implemented, passed |
| 1.11 | `mem_negative_offset` | Negative immediate offsets on loads and stores | A negative-offset access reaches the same word as the equivalent positive-offset access | Implemented, passed |
| 1.12 | `mem_byte_to_word_scaling` | Byte addresses are converted to word indices | Byte addresses 4, 8, 12 read preloaded words 1, 2, 3 | Implemented, passed |
| 1.13 | `data0_preservation` | `data[0]` is never written | `dmem[0]` is 0 after a program of stores elsewhere, and no observed store targets word 0 | Withdrawn |
| 1.14 | `sw_does_not_write_rd` | S-type immediate bits in the rd field do not cause a register write | The register aliased by `imm[4:0]` is unchanged | Implemented, passed |
| 1.15 | `lw_into_x0` | A load targeting x0 is discarded | x0 reads 0 after `lw x0` of a nonzero value | Implemented, passed |
| 1.16 | `beq_taken_forward` | A taken branch redirects the PC forward | The skipped instruction leaves no trace | Implemented, passed |
| 1.17 | `beq_not_taken` | A not-taken branch falls through | The following instruction executes | Implemented, passed |
| 1.18 | `beq_backward_loop` | Negative branch offsets and repeated execution | A three-iteration loop produces the correct accumulator | Implemented, passed |
| 1.19 | `beq_equal_nonzero` | Equality between two nonzero registers | The branch is taken when rs1 == rs2 and neither is x0 | Implemented, passed |
| 1.20 | `ebreak_halt_pulse` | `ebreak` halts and pulses `cpu_halted` exactly once | One halt observation; prior results intact | Partly covered |
| 1.21 | `no_execution_past_ebreak` | Execution stops at `ebreak` | The instruction after `ebreak` leaves no trace | Implemented, passed |
| 1.22 | `unsupported_encoding_is_nop` | An unsupported encoding behaves as a no-op | PC advances; surrounding instructions unaffected | Implemented, passed |
| 1.23 | `ownership_handoff` | Memory ownership transfers at start and halt | External accesses succeed before start and after halt; `cpu_active` tracks the transition | Partly covered |
| 1.24 | `reg_window_read_only` | The register window rejects writes | A program-set register value survives an attempted external write | Not implemented |
| 1.25 | `unmapped_window` | Accesses to `addr[13:12] == 2'b11` | The port behaves as its contract says, without hanging the testbench | Not implemented |
| 1.26 | `store_then_load_same_word` | A load immediately after a store to the same word | The load returns the just-stored value | Implemented, passed |
| 1.27 | `branch_on_just_written_reg` | A branch whose condition register was written by the previous instruction | The branch resolves on the new value | Implemented, passed |
| 1.28 | `reset_while_active` | Reset in the middle of a program clears the registers (reviewer request) | Register readback after the reset is all zeros | Implemented, passed |
| 1.29 | `external_halt_loop` | An external halt request stops a program that never halts by itself (reviewer request) | `cpu_active` is high before the request and low after it | Implemented, passed |
| 1.30 | `ext_mem_boundaries` | First and last word of both SRAMs are written and read back (reviewer request) | All four reads match the scoreboard's copy | Implemented, passed |

---

## Functional-test details

**Note on the initial state.** The initial state in each entry is the plan as written. In the implemented tests, `init_memories()` fills data memory with random values before every test, and the reference model supplies the expected values. Where an expected value depends on that memory (for example 1.12 and 1.21), the reference model gives the real expected value.


### 1.1 — `addi_imm_limits`

**Functionality:** I-type immediate sign extension across the full 12-bit
signed range.

**Why this test:** A decoder that zero-pads instead of sign-extending produces
correct results for every positive immediate and wrong results for every
negative one. Testing only `addi x1, x0, 5` would pass on a broken
implementation. The four values chosen are the two range endpoints, the
all-ones case, and zero.

**Initial state:**
- Registers: all 0 (post-reset)
- Data memory: all 0
- Other setup: none

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(2047)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(-2048)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(-1)),
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(0)),
  asm_instr(.op(OP_ADDI), .rd(5), .rs1(0), .imm(1)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_07FF` | 0 + 2047, maximum positive 12-bit immediate |
| x2 | `32'hFFFF_F800` | 0 + (−2048), minimum negative; sign-extended from `100000000000` |
| x3 | `32'hFFFF_FFFF` | 0 + (−1); every extension bit set |
| x4 | `32'h0000_0000` | 0 + 0 |
| x5 | `32'h0000_0001` | 0 + 1 |

**Pass criteria:** All five registers match after halt. x2 and x3 specifically
distinguish sign extension from zero padding.

**Final result:** Passed on my CPU with 0 scoreboard mismatches. The test in the testbench has three of the five planned values (2047, -2048 and -1). The cases 0 and 1 are not in it. They add little, because only the negative values exercise sign extension.

---

### 1.2 — `raw_dependency_chain`

**Functionality:** A register written by one instruction is readable by the
next.

**Why this test:** Register writes and register reads happen in different
cycles. If writeback commits late, or the register read happens before the
previous write lands, each instruction reads a stale value. A chain makes the
error compound so it cannot be masked by a coincidentally-correct value.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(7)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(1), .imm(-3)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(2), .imm(100)),
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(3), .imm(-104)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0007` | 0 + 7 |
| x2 | `32'h0000_0004` | 7 − 3, reads x1 written one instruction earlier |
| x3 | `32'h0000_0068` | 4 + 100 |
| x4 | `32'h0000_0000` | 104 − 104 |

**Pass criteria:** All four correct. If the register file returns stale data,
x2 is −3 and the rest of the chain is not right.

**Final result:** Passed. The program in the testbench has two instructions, not the four planned.

---

### 1.3 — `x0_write_protection`

**Functionality:** Writes targeting x0 are discarded.

**Why this test:** Two separate mechanisms could fail. An instruction with
`rd == 0` must not modify the register array, and reads of x0 must return zero
regardless. This test drives both an I-type and an R-type write at x0, then
reads x0 as a source to confirm it is still zero.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
  asm_instr(.op(OP_ADDI), .rd(0), .rs1(0), .imm(99)),
  asm_instr(.op(OP_ADD),  .rd(0), .rs1(1), .rs2(1)),
  asm_instr(.op(OP_ADD),  .rd(2), .rs1(0), .rs2(0)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x0 | `32'h0000_0000` | Both writes discarded |
| x1 | `32'h0000_0005` | Unaffected |
| x2 | `32'h0000_0000` | x0 + x0, proves x0 still sources zero |

**Pass criteria:** x0 and x2 both zero. x2 is the stronger check — it fails
even if the register window read of x0 is hardwired to zero while the
underlying storage was corrupted.

**Final result:** Passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.4 — `x0_source_reads_zero`

**Functionality:** x0 reads as zero in both source operand positions.

**Why this test:** 1.3 checks the write side. This checks that x0 reads zero
through rs1 and rs2 independently, in case only one read port implements the
special case.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(50)),
  asm_instr(.op(OP_SUB),  .rd(2), .rs1(1), .rs2(0)),
  asm_instr(.op(OP_SUB),  .rd(3), .rs1(0), .rs2(1)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0032` | 50 |
| x2 | `32'h0000_0032` | 50 − 0, x0 read through rs2 |
| x3 | `32'hFFFF_FFCE` | 0 − 50 = −50, x0 read through rs1 |

**Pass criteria:** Both subtractions correct. x3 also confirms a negative
result from the ALU.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.5 — `add_value_classes`

**Functionality:** Register-register addition across value classes, including
32-bit wraparound.

**Why this test:** Small positive sums prove almost nothing. Mixed-sign
addition exercises the carry path, and `0x80000000 + 0x80000000` checks that
the result truncates to 32 bits rather than producing a wider value or
saturating.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),
  asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),
  asm_instr(.op(OP_ADD),  .rd(4), .rs1(3), .rs2(3)),
  asm_instr(.op(OP_ADDI), .rd(5), .rs1(0), .imm(100)),
  asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(-40)),
  asm_instr(.op(OP_ADD),  .rd(7), .rs1(5), .rs2(6)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x3 | `32'h8000_0000` | 1 << 31, builds a value larger than any immediate |
| x4 | `32'h0000_0000` | 0x80000000 + 0x80000000 wraps to 0 in 32 bits |
| x7 | `32'h0000_003C` | 100 + (−40) = 60, mixed sign |

**Pass criteria:** x4 is 0, not a saturated or sign-flipped value.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.6 — `sub_value_classes`

**Functionality:** Subtraction producing positive, negative, and zero results.

**Why this test:** `sub` shares an opcode and funct3 with `add` and is
distinguished only by one bit of funct7. A decoder that ignores funct7 performs
addition for both, which produces a wrong-but-plausible answer. The negative
and zero cases also check the result path used by `beq`'s equality comparison.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(3)),
  asm_instr(.op(OP_SUB),  .rd(3), .rs1(1), .rs2(2)),
  asm_instr(.op(OP_SUB),  .rd(4), .rs1(2), .rs2(1)),
  asm_instr(.op(OP_SUB),  .rd(5), .rs1(1), .rs2(1)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x3 | `32'h0000_0002` | 5 − 3 |
| x4 | `32'hFFFF_FFFE` | 3 − 5 = −2 |
| x5 | `32'h0000_0000` | 5 − 5; the zero case `beq` depends on |

**Pass criteria:** All three correct. If x3 is 8, the decoder is treating `sub`
as `add`.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.7 — `sll_shift_amount_masking`

**Functionality:** The shift amount uses only bits [4:0] of rs2.

**Why this test:** The RISC-V specification requires the upper bits of the
shift amount to be ignored. An implementation that passes the full register
value to a shift operator produces zero for a shift of 32, where the correct
answer is the unshifted operand. This is the single highest-value shift test
because the failure is invisible for every shift amount under 32.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(0)),
  asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(31)),
  asm_instr(.op(OP_SLL),  .rd(5), .rs1(1), .rs2(4)),
  asm_instr(.op(OP_ADDI), .rd(6), .rs1(0), .imm(32)),
  asm_instr(.op(OP_SLL),  .rd(7), .rs1(1), .rs2(6)),
  asm_instr(.op(OP_ADDI), .rd(8), .rs1(0), .imm(33)),
  asm_instr(.op(OP_SLL),  .rd(9), .rs1(1), .rs2(8)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x3 | `32'h0000_0001` | 1 << 0 |
| x5 | `32'h8000_0000` | 1 << 31, the last legal shift |
| x7 | `32'h0000_0001` | 32 & 0x1F = 0, so no shift occurs |
| x9 | `32'h0000_0002` | 33 & 0x1F = 1 |

**Pass criteria:** x7 is 1 and x9 is 2. An unmasked implementation gives 0 for
both.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.8 — `srl_is_logical`

**Functionality:** Right shift fills vacated bits with zeros.

**Why this test:** `srl` and `sra` differ only in fill behavior, and the
difference is invisible unless the operand's MSB is set. This test builds
`0x80000000` first specifically so the fill is observable.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),
  asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(1)),
  asm_instr(.op(OP_SRL),  .rd(5), .rs1(3), .rs2(4)),
  asm_instr(.op(OP_SRL),  .rd(6), .rs1(3), .rs2(2)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x3 | `32'h8000_0000` | 1 << 31 |
| x5 | `32'h4000_0000` | Logical shift right by 1; arithmetic would give `0xC000_0000` |
| x6 | `32'h0000_0001` | 0x80000000 >> 31 |

**Pass criteria:** x5 is `0x4000_0000`. Any value with the top bit set means
the shift is arithmetic.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.9 — `shift_by_computed_amount`

**Functionality:** The shift amount is read from a register at runtime.

**Why this test:** In every other shift test the shift amount is set by an
immediately preceding `addi`, which could mask a decoder that reads the shift
amount from the wrong field. Here the amount is computed by arithmetic, so a
decoder reading an immediate field instead of rs2 produces a visibly wrong
result.

**Initial state:** registers 0, data memory 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(10)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(6)),
  asm_instr(.op(OP_SUB),  .rd(3), .rs1(1), .rs2(2)),
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(3)),
  asm_instr(.op(OP_SLL),  .rd(5), .rs1(4), .rs2(3)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x3 | `32'h0000_0004` | 10 − 6, the computed shift amount |
| x5 | `32'h0000_0030` | 3 << 4 = 48 |

**Pass criteria:** x5 is 48.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.10 — `sw_lw_roundtrip_distinct_words`

**Functionality:** Stores and loads reach the intended distinct memory words.

**Why this test:** A single store-and-reload at one address passes even if the
address calculation is completely wrong, because the same wrong address is used
both times. Two values at two addresses, read back in the opposite order,
detect collapsing or aliasing.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(42)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(99)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(2), .imm(8)),
  asm_instr(.op(OP_LW),   .rd(3), .rs1(0), .imm(8)),
  asm_instr(.op(OP_LW),   .rd(4), .rs1(0), .imm(4)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| dmem[1] | `32'h0000_002A` | 42 stored at byte 4 = word 1 |
| dmem[2] | `32'h0000_0063` | 99 stored at byte 8 = word 2 |
| x3 | `32'h0000_0063` | Loaded from byte 8 |
| x4 | `32'h0000_002A` | Loaded from byte 4 |

**Pass criteria:** Both memory words and both registers correct. Loading in
reverse order means a design that returns the most recent store regardless of
address fails.

**Additional observation:** The monitor should report exactly two `CPU_STORE`
transactions, at word addresses 1 and 2, and exactly two `CPU_LOAD`
transactions at the same addresses.

**Final result:** Passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.11 — `mem_negative_offset`

**Functionality:** Negative immediate offsets on loads and stores.

**Why this test:** Load and store offsets are sign-extended immediates, and a
store uses the S-type layout while a load uses I-type. A sign-extension bug in
either path is invisible with positive offsets. Reaching the same word by two
different address computations proves the arithmetic, not just that something
was written somewhere.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(16)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(77)),
  asm_instr(.op(OP_SW),   .rs1(1), .rs2(2), .imm(-8)),
  asm_instr(.op(OP_LW),   .rd(3), .rs1(1), .imm(-8)),
  asm_instr(.op(OP_LW),   .rd(4), .rs1(0), .imm(8)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| dmem[2] | `32'h0000_004D` | 16 + (−8) = byte 8 = word 2 |
| x3 | `32'h0000_004D` | Load with the same negative offset |
| x4 | `32'h0000_004D` | Load of byte 8 with a zero base; same word |

**Pass criteria:** x3 and x4 are equal and correct, and `dmem[2]` holds the
value. If sign extension fails on the store, the write lands near word 6
(16 + 2040 in bytes) instead.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.12 — `mem_byte_to_word_scaling`

**Functionality:** Byte addresses are converted to word indices before
reaching the SRAM.

**Why this test:** The external port and the program both use byte addresses,
but the SRAM is word-indexed. An implementation that omits the divide-by-four
reads word 4 when the program asks for byte 4. Preloading distinct values at
consecutive words makes the off-by-four immediately visible rather than
returning a plausible zero.

**Initial state:**
- Registers: all 0
- Data memory (written through the external port before start):

| Word | Value |
| --- | --- |
| dmem[0] | `32'h0000_0000` |
| dmem[1] | `32'h1111_1111` |
| dmem[2] | `32'h2222_2222` |
| dmem[3] | `32'h3333_3333` |
| dmem[4] | `32'h4444_4444` |

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_LW), .rd(1), .rs1(0), .imm(4)),
  asm_instr(.op(OP_LW), .rd(2), .rs1(0), .imm(8)),
  asm_instr(.op(OP_LW), .rd(3), .rs1(0), .imm(12)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h1111_1111` | Byte 4 = word 1 |
| x2 | `32'h2222_2222` | Byte 8 = word 2 |
| x3 | `32'h3333_3333` | Byte 12 = word 3 |

**Pass criteria:** All three match. An unscaled implementation returns
`0x4444_4444` for x1 and zeros for the rest.

**Additional observation:** Monitor `CPU_LOAD` transactions should report word
addresses 1, 2, and 3 — checking the address stream directly rather than
inferring it from the loaded data.

**Final result:** Passed. The plan preloaded distinct values. The test relies on the random values from init_memories(), and the scoreboard supplies the expected data.

---

### 1.13 — `data0_preservation`

**Functionality:** Data memory word 0 is never written.

**Why this test:** This is an explicit requirement. The failure mode is a store
write-enable that is asserted outside the intended cycle — during fetch, during
writeback, or for a non-store instruction — while the address bus happens to
hold zero. Checking only the final value of `dmem[0]` would miss a write that
stored zero to word 0, so the store stream is checked as well.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(8)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1020)),
  asm_instr(.op(OP_SW),   .rs1(2), .rs2(1), .imm(0)),
  asm_instr(.op(OP_ADD),  .rd(3), .rs1(1), .rs2(1)),
  asm_instr(.op(OP_LW),   .rd(4), .rs1(0), .imm(4)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| dmem[0] | `32'h0000_0000` | Never targeted |
| dmem[1] | `32'hFFFF_FFFF` | Store at byte 4 |
| dmem[2] | `32'hFFFF_FFFF` | Store at byte 8 |
| dmem[255] | `32'hFFFF_FFFF` | Store at byte 1020, near the top of memory |

**Pass criteria:**
1. `dmem[0]` reads zero after halt.
2. The monitor observes exactly three `CPU_STORE` transactions, none with
   address 0.

The second criterion is the stronger one. The program deliberately mixes
non-store instructions between the stores so that a write-enable asserted in
the wrong state would show up as an extra `CPU_STORE`.

**Final result:** Withdrawn. The premise was wrong. init_memories() fills data word 0 with a random value, and random program 13 stored to word 0 with 0 scoreboard mismatches, so the reference model treats that store as legal. The scoreboard checks the store stream and final memory instead. Assertion NO_STORE_TO_DATA0 was withdrawn for the same reason (evidence_NO_STORE_TO_DATA0.log).

---

### 1.14 — `sw_does_not_write_rd`

**Functionality:** The S-type immediate occupying instruction bits [11:7] does
not cause a register write.

**Why this test:** In the S-type layout the low five immediate bits sit exactly
where an R-type or I-type instruction keeps its destination register. A decoder
that asserts the register write enable based on opcode alone, or that forgets
to clear it for stores, will write the ALU result into whichever register those
immediate bits happen to name. With an offset of 4, `imm[4:0]` is `00100`, so
the aliased register is x4. This test loads x4 with a sentinel first so the
corruption is visible.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(123)),
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(55)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| x4 | `32'h0000_007B` | 123, unchanged by the store |
| x1 | `32'h0000_0037` | 55 |
| dmem[1] | `32'h0000_0037` | 55 stored at byte 4 |

**Pass criteria:** x4 still holds 123. If the store writes a register, x4 holds
the computed store address (4) instead.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.15 — `lw_into_x0`

**Functionality:** A load whose destination is x0 is discarded.

**Why this test:** 1.3 covers ALU results written to x0. A load takes a
different path to the register file — the data comes from memory rather than
the ALU — so the x0 guard must hold on that path too.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(7)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
  asm_instr(.op(OP_LW),   .rd(0), .rs1(0), .imm(4)),
  asm_instr(.op(OP_ADD),  .rd(2), .rs1(0), .rs2(0)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x0 | `32'h0000_0000` | Load discarded |
| x2 | `32'h0000_0000` | x0 + x0 |

**Pass criteria:** Both zero. If the load reached the register array, x2 is 14.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.16 — `beq_taken_forward`

**Functionality:** A taken branch redirects the PC forward.

**Why this test:** The skipped instruction is chosen to write a register that
is otherwise zero, so its execution leaves unambiguous evidence. Checking only
that the program halted would not distinguish a taken branch from a fall-through.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(0)),   // byte 0
  asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),  // byte 4, target byte 12
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),   // byte 8, must not run
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(2)),   // byte 12
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0000` | 0 |
| x2 | `32'h0000_0000` | Skipped; still at its reset value |
| x3 | `32'h0000_0002` | Branch target executed |

**Pass criteria:** x2 is 0 and x3 is 2.

**Note:** Branch offset is a byte offset from the branch instruction's own
address, confirmed against `encode()` in `cpu_seq_item.svh`.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.17 — `beq_not_taken`

**Functionality:** A branch whose condition is false falls through.

**Why this test:** The complement of 1.16. Together they prove the condition is
evaluated rather than the branch being always-taken or never-taken. Only the
initial value of x1 differs between the two programs, which isolates the
condition as the single variable.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(2)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0001` | 1, so x1 != x0 |
| x2 | `32'h0000_0001` | Executed because the branch was not taken |
| x3 | `32'h0000_0002` | Executed |

**Pass criteria:** x2 is 1.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.18 — `beq_backward_loop`

**Functionality:** Negative branch offsets and repeated execution of the same
instructions.

**Why this test:** Forward branches only exercise positive offsets. A loop
tests the sign extension of the B-type immediate — which is the most heavily
scrambled immediate format in the ISA — and confirms the CPU can re-execute
instructions rather than only moving forward. The accumulator value encodes the
iteration count, so an off-by-one loop produces a distinguishable wrong answer
rather than just hanging.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(3)),    // byte 0  counter
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(0)),    // byte 4  accumulator
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(2), .imm(10)),   // byte 8  loop body
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(1), .imm(-1)),   // byte 12
  asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),   // byte 16, exit to byte 24
  asm_instr(.op(OP_BEQ),  .rs1(0), .rs2(0), .imm(-12)), // byte 20, back to byte 8
  EBREAK_WORD                                            // byte 24
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0000` | Counter decremented 3 → 0 |
| x2 | `32'h0000_001E` | 10 added three times = 30 |

**Pass criteria:** x2 is exactly 30. A four-iteration loop gives 40 and a
two-iteration loop gives 20, so the value identifies the error rather than just
reporting one.

**Coverage note:** `c_branch_target` as supplied constrains `imm >= 4`, so
constrained-random stimulus generates forward branches only. This directed
test is therefore the only coverage of negative branch offsets in the entire
suite. If coverage closure shows the backward-branch path in the DUT is
unexercised, that is the reason, and the options are to widen the constraint
or to add further directed cases here. Recorded now so the gap is deliberate
rather than discovered late.

**Watchdog note:** If the backward branch target is wrong the program may never
reach `ebreak`. The bounded halt timeout must record a failure and reset rather
than hanging the suite.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.19 — `beq_equal_nonzero`

**Functionality:** Equality comparison between two nonzero registers.

**Why this test:** The stated requirement is `beq` against x0, and every other
branch test uses x0 as one operand. If the comparison is implemented as "is rs1
zero" rather than "is rs1 equal to rs2," all of those tests still pass. This
test uses two equal nonzero registers, which only a true equality comparison
handles.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),
  asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(2), .imm(8)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(2)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x3 | `32'h0000_0000` | Skipped by the taken branch |
| x4 | `32'h0000_0002` | Branch target |

**Pass criteria:** x3 is 0. A zero-detect implementation falls through and x3
becomes 1.

**Note:** This exceeds the stated `beq`-against-x0 requirement. If the DUT
intentionally supports only the x0 form, this test documents that limitation
rather than reporting a defect; the distinction should be recorded in the final
plan.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.20 — `ebreak_halt_pulse`

**Functionality:** `ebreak` halts execution and `cpu_halted` pulses exactly
once.

**Why this test:** The README states `cpu_halted` pulses and must be sampled
every cycle rather than treated as a level. Two failures are possible: no pulse
at all (the suite hangs until the timeout), or a signal that stays high and is
counted repeatedly. Counting observations distinguishes them.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  EBREAK_WORD
};
```

**Expected result:**

| Observation | Expected |
| --- | --- |
| `CPU_HALT` transactions | Exactly 1 |
| x1 | `32'h0000_0001` |
| `cpu_active` after halt | Low, memories returned to the external port |

**Pass criteria:** One halt observation, not zero and not many. x1 confirms the
instruction before `ebreak` retired rather than being lost to an early halt.

**Final result:** Partly covered. Every test ends in ebreak and the driver waits for the halt pulse, so a missing pulse would time out. Not checked: that the pulse occurs exactly once.

---

### 1.21 — `no_execution_past_ebreak`

**Functionality:** No instruction after `ebreak` executes.

**Why this test:** A halt signal that is combinational rather than registered
would deassert as soon as the instruction wire changes, letting the CPU resume.
Placing a register write after the `ebreak` makes any continued execution
visible in architectural state.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  EBREAK_WORD,
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(99)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(2), .imm(4)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0001` | Executed before the halt |
| x2 | `32'h0000_0000` | Never executed |
| dmem[1] | `32'h0000_0000` | The store after `ebreak` never occurred |

**Pass criteria:** x2 and `dmem[1]` are zero, and the monitor observes zero
`CPU_STORE` transactions.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.22 — `unsupported_encoding_is_nop`

**Functionality:** An unsupported instruction encoding behaves as a no-op and
the PC still advances.

**Why this test:** `cpu_tb_pkg.sv` documents `OP_NOP` as representing
unsupported encodings that both the DUT specification and the reference model
treat as no-ops. Two failure modes matter: the CPU performs some unintended
action, or it stalls and never reaches the following instruction. Placing
known-good instructions on both sides detects either.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
  asm_instr(.op(OP_NOP)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0005` | Before the no-op |
| x2 | `32'h0000_0007` | After the no-op; proves the PC advanced past it |
| All others | `32'h0000_0000` | The no-op wrote nothing |

**Pass criteria:** x2 is 7 and no other register changed. If the program times
out, the unsupported encoding stalled the pipeline.

**Encoding:** `asm_instr(.op(OP_NOP))` produces `32'h0000_0000` via the
`default` arm of `encode()`. Opcode field `7'b0000000` matches nothing in the
supported set.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.23 — `ownership_handoff`

**Functionality:** Memory ownership transfers from the external port to the CPU
at start and back at halt.

**Why this test:** This is a chip-level behavior with no instruction attached,
and it is the precondition for every other test — if the program write does not
land before the CPU starts, every functional test is meaningless. The
transition is observable through `cpu_active` and through whether external
accesses are serviced.

**Sequence:**
1. Reset the chip; confirm all testbench-driven signals are at idle.
2. Write a short program into instruction SRAM through the external port.
3. Read one program word back and compare it with what was written.
4. Write a sentinel into `dmem[3]` and read it back.
5. Confirm `cpu_active` is low.
6. Pulse `en_cpu` for one cycle.
7. Confirm `cpu_active` goes high.
8. Wait for the halt pulse with a bounded timeout.
9. Confirm `cpu_active` returns low.
10. Read the register window and data SRAM and compare with the reference model.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(21)),
  asm_instr(.op(OP_LW),   .rd(2), .rs1(0), .imm(12)),
  EBREAK_WORD
};
```

**Expected result:**

| Observation | Expected |
| --- | --- |
| Program readback (step 3) | Matches the written word exactly |
| `dmem[3]` readback (step 4) | Matches the sentinel |
| `cpu_active` before start | Low |
| `cpu_active` during execution | High |
| `cpu_active` after halt | Low |
| x2 after halt | The sentinel, proving the pre-loaded data survived the handoff |

**Pass criteria:** The instruction readback matches, `cpu_active` follows the
expected sequence, and the CPU observed the data written before it started.

**Dependency:** Step behavior for an external access attempted while
`cpu_active` is high depends on open question 4 and will be added once the
contract is confirmed.

**Final result:** Partly covered. Every test writes the program before starting the CPU and reads state after the halt, so the handoff works in the normal flow. HALT_RELEASES_CPU checks cpu_active after an external halt. Not checked: an external access made while cpu_active is high (open question 4).

---

### 1.24 — `reg_window_read_only`

**Functionality:** The register-file window at `REG_BASE` rejects writes.

**Why this test:** `window_of()` classifies the window but the read-only
property is a separate guarantee. If a write were accepted, the register
readback used by every other test would be reporting testbench-written values
rather than DUT state, and the whole suite could pass falsely.

**Sequence:**
1. Reset.
2. Load a program that sets x1 to a known value.
3. Before starting the CPU, attempt an external write of a different sentinel
   to `word_addr(REG_BASE, 1)`.
4. Start the CPU and wait for halt.
5. Read `word_addr(REG_BASE, 1)`.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(64)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| Register window word 1 | `32'h0000_0040` | 64, written by the program, not the external sentinel |

**Pass criteria:** The readback is 64. If it is the sentinel, the window is
writable and the read path is untrustworthy.

**Final result:** Not implemented. c_reg_read_only keeps random traffic from writing the register window, and no directed test attempts it.

---

### 1.25 — `unmapped_window`

**Functionality:** Accesses with `addr[13:12] == 2'b11` behave per contract.

**Why this test:** `window_of()` defines `WIN_NONE`, so the testbench must know
what a `WIN_NONE` access does. Whatever the answer, the driver needs a bounded
wait so an unmapped read cannot hang the suite, and the monitor needs to
classify the transaction correctly rather than mistaking it for a real access.

**Sequence:**
1. Reset, CPU disabled.
2. Attempt a read at an address with `addr[13:12] == 2'b11`.
3. Wait for `rready` with a bounded timeout.
4. Record whether a response arrived and what `rdata` held.

**Expected result:** To be specified once open question 3 is resolved. The test
will assert the documented contract, whichever it is.

**Pass criteria:** The testbench terminates the access within the timeout and
classifies it correctly. A hang is a testbench defect, not a DUT defect, and
this test exists partly to prove the driver handles the case.

**Final result:** Not implemented. c_valid_window keeps random traffic out of the unmapped window, and no directed test attempts it. Open question 3 was never answered.

---

### 1.26 — `store_then_load_same_word`

**Functionality:** A load immediately following a store to the same word
returns the stored value.

**Why this test:** This is the memory equivalent of the register dependency in
1.2. The store and the load are separate memory transactions in adjacent
instructions; if the store has not committed when the load's address goes out,
the load returns the old contents. Preloading the target word with a distinct
non-zero value means a stale read is visibly wrong rather than returning a
plausible zero.

**Initial state:**
- Registers: all 0
- Data memory: `dmem[1] = 32'hDEAD_BEEF`, all others 0

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(88)),
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(4)),
  asm_instr(.op(OP_LW),   .rd(2), .rs1(0), .imm(4)),
  EBREAK_WORD
};
```

**Expected result:**

| Location | Expected value | Calculation |
| --- | --- | --- |
| dmem[1] | `32'h0000_0058` | 88, overwriting the preload |
| x2 | `32'h0000_0058` | The just-stored value, not `0xDEAD_BEEF` |

**Pass criteria:** x2 is 88. If it is `0xDEAD_BEEF`, the load raced the store.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.27 — `branch_on_just_written_reg`

**Functionality:** A branch condition register written by the immediately
preceding instruction is read correctly.

**Why this test:** Branch resolution and register writeback may commit in
different cycles. If the branch reads its condition register before the
previous instruction's write lands, it resolves on stale data. This is the
same class of failure as 1.2 but on the control path rather than the data path,
and it is not covered by 1.16 because there the condition register was set two
instructions earlier.

**Initial state:** registers 0, data memory all 0.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),   // x1 = 5
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(0)),   // x1 = 0, immediately before the branch
  asm_instr(.op(OP_BEQ),  .rs1(1), .rs2(0), .imm(8)),  // taken only if the new value is seen
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(2)),
  EBREAK_WORD
};
```

**Expected result:**

| Register | Expected value | Calculation |
| --- | --- | --- |
| x1 | `32'h0000_0000` | Overwritten to 0 |
| x2 | `32'h0000_0000` | Skipped by the taken branch |
| x3 | `32'h0000_0002` | Branch target |

**Pass criteria:** x2 is 0. If the branch read the stale value 5, it falls
through and x2 becomes 1.

**Final result:** Everything passed on my CPU with 0 scoreboard mismatches. Expected values come from the reference model.

---

### 1.28 — `reset_while_active` (added after review)

**Functionality:** A reset in the middle of a program clears the registers and stops the CPU.

**Why this test:** Reset can arrive while the CPU is running. The registers must be cleared and the CPU must stop.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
  asm_instr(.op(OP_BEQ),  .rs1(0), .rs2(0), .imm(0)),   // loops forever
  EBREAK_WORD
};
```

**Steps:** reset, load the program, start the CPU, wait 15 clocks, check that `cpu_active` is high, reset again, check that `cpu_active` is low, then read all 32 registers.

**Expected result:** all 32 registers read `32'h0000_0000`. The scoreboard clears its expected registers on reset.

**Pass criteria:** 0 scoreboard mismatches and no `assertion_fail` message.

**Final result:** Passed. The readback after the reset shows all zeros. The loop makes the reference model print "did not halt after 100000 instructions", which is expected and does not fail the run. Limit: the test does not check that x1 held 5 before the reset.

---

### 1.29 — `external_halt_loop` (added after review)

**Functionality:** An external halt request stops a program that never halts by itself.

**Why this test:** A program that does not reach `ebreak` can only be stopped from outside.

**Program:**
```systemverilog
prog = '{
  asm_instr(.op(OP_BEQ), .rs1(0), .rs2(0), .imm(0)),    // loops forever
  EBREAK_WORD
};
```

**Steps:** reset, load the program, start the CPU, wait 10 clocks, check that `cpu_active` is high, pulse `halt_cpu`, check that `cpu_active` is low.

**Expected result:** `cpu_active` is high before the request and low after it.

**Pass criteria:** no `assertion_fail` message. The driver's halt wait also stops after 100 cycles if `cpu_active` never drops.

**Final result:** Passed. `HALT_RELEASES_CPU` watches the same behavior on every run. The test does not check `cpu_halted`.

---

### 1.30 — `ext_mem_boundaries` (added after review)

**Functionality:** The first and last word of both SRAMs can be written and read through the external port.

**Why this test:** The edges of each window are where an address decode error would show up, and a bad decode could make two windows overlap.

**Steps:** write a different value to byte addresses `0x0000`, `0x0FFC`, `0x1000` and `0x1FFC`, then read all four back.

**Expected result:** each read returns the value written to that address. The scoreboard compares every read with its own copy of memory.

**Pass criteria:** 0 scoreboard mismatches.

**Final result:** Passed. The log shows matching reads of `imem[0x000]`, `imem[0x3ff]`, `dmem[0x000]` and `dmem[0x3ff]`.

---

### Tests added during the bug hunt

The 25 `min_*` tests in `cpu_tb_top.sv` were added to shrink the random failures into small reproducers. They were not in the initial plan. All of them pass on my CPU. The ones named in section 4 fail on the encrypted CPU, and the rest pass on both and were used to rule out other explanations.

---

# 2. Constrained-random tests

## Instruction constraints

| Constraint | Provided, partial, or open | Behavior and purpose | Final implementation summary |
| --- | --- | --- | --- |
| `c_opcode` | Provided | Restricts `op` to the supported instruction set so generated programs contain only encodings the DUT and reference model both define. Without it, most random programs would be unsupported encodings and would exercise almost nothing. | No member change |
| `c_reg_bias` | Provided | Weights the register selection so a small set of registers is reused often. Uniform selection across 32 registers makes read-after-write dependencies rare; biasing creates them, which is where timing bugs appear. | No member change |
| `c_imm_range` | Partial | Supplied code constrains only `imm >= -2048`, leaving the upper end unbounded, so generated immediates can exceed what a 12-bit signed field can hold and `encode()` would silently truncate them. Completion must add `imm <= 2047`. Planned completion also biases toward the endpoints and zero so the sign-extension boundary in 1.1 is hit regularly by random stimulus rather than only by the directed test. | Removes: immediates outside -2048 to 2047, which `encode()` would cut off. Encourages: the corner values -2048, -1, 0, 1 and 2047 for `addi` only. Unreachable: nothing for `addi`. Other instructions get their immediates from their own constraints. |
| `c_mem_align` | Open | Must force load and store effective addresses to be word-aligned and within the 1024-word data SRAM. Requires constraining the base register value together with the offset, since the effective address is their sum. Planned approach: bias the base toward x0 and bound the offset to a multiple of 4 inside the memory range. | Removes: negative and unaligned immediates for `lw` and `sw`. Encourages: every word-aligned offset from 0 to 4092. Unreachable: negative offsets, which only directed test 1.11 covers. Limit: it does not use the base register, so the final address can still fall outside data memory. The README asks for a version that uses `reg_snapshot`. I did not implement it because I could not pull the updated scaffold (`git fetch` returned a 403 error). |
| `c_imm_unused` | Provided | Forces the immediate field to a fixed value for instruction types that do not use it, so R-type programs are reproducible and the unused field cannot accidentally alias into a decoder path. | No member change |
| `c_branch_target` | Partial | Supplied code constrains `(imm % 4 == 0) && (imm >= 4)`, which forces every generated branch forward and word-aligned. The forward restriction is what the TODO means by "avoid loops," but it also means random stimulus can never exercise a negative branch offset — that path is covered only by directed test 1.18. What is still missing is an upper bound tying the offset to the remaining program length, so a forward target cannot land past the final `ebreak`. Planned completion bounds `imm` by `(prog_len - idx) * 4`. | Removes: unaligned, zero and backward offsets, and offsets beyond the program length. Encourages: forward branches of 4 to `(prog_len - idx) * 4` bytes. Unreachable: backward branches and loops, which only directed test 1.18 covers. |
| `c_no_branch_at_end` | Provided | Prevents a branch in the final positions, where a forward target would fall outside the program. Keeps every generated program terminating at its `ebreak`. | No member change |
| `c_branch_taken_bias` | Open | Must make taken branches occur at a useful rate. Unconstrained random register values are almost never equal, so nearly every branch falls through and the taken path goes untested. Planned approach: force one branch operand to x0 with some probability and bias the other toward zero, so the taken path is exercised without eliminating the not-taken path. | Removes: nothing. Encourages: taken branches. `rs2` equals `rs1` with weight 1, against weight 1 for any register from 0 to 31, so about half of the branches compare a register with itself. Unreachable: nothing. Not-taken branches still happen. |

## External-port constraints

| Constraint | Provided, partial, or open | Behavior and purpose | Final implementation summary |
| --- | --- | --- | --- |
| `c_align` | Provided | Forces external addresses to be word-aligned, matching the port requirement that accesses are word-aligned. | No member change |
| `c_valid_window` | Partial | Must restrict `addr[13:12]` to mapped windows for ordinary traffic. Planned completion excludes `2'b11` from the default distribution while leaving a directed path for the unmapped-window test in 1.25. | Removes: the unmapped window and register word indexes of 32 or more. Encourages: both SRAM windows and the register window. Unreachable: the unmapped window in random traffic. Directed test 1.25 was not implemented. |
| `c_reg_read_only` | Provided | Prevents generating writes to the register window, which is read-only. Without it, random traffic would attempt illegal writes and the scoreboard would need to special-case them. | No member change |
| `c_data_corners` | Open | Must bias external write data toward corner values rather than uniformly random 32-bit numbers. Planned set: 0, 1, `0xFFFF_FFFF`, `0x8000_0000`, `0x7FFF_FFFF`, and values with a single bit set. These are the values most likely to expose sign, carry, and truncation bugs when later loaded and operated on. | Removes: nothing. Encourages: the values 0, 1, `0xFFFFFFFF`, `0x80000000` and `0x7FFFFFFF` (weight 1 each, about 55% of the weight in total with the two ranges below), plus two broad ranges, `0x00000002` to `0x7FFFFFFE` and `0x80000001` to `0xFFFFFFFE` (weight 2 each). Unreachable: nothing. Single-bit values from the planned column are not included. |

## Random-program test

| Item | Final |
| --- | --- |
| Programs per run | 20 |
| Program length | 5 to 30 random instructions, chosen with `$urandom_range(5, 30)`, plus a final `ebreak` |
| Checked after each program | all 32 registers and data words 0 to 15 are read back and compared with the reference model. The scoreboard also compares the order of CPU stores. |
| Logged for reproduction | the numeric SVSEED printed by Xcelium, a `RANDOM PROGRAM n of 20` line, and the full generated program |

Each iteration runs the same steps: reset, `init_memories()`, generate and load the program, start the CPU, wait for the halt with a 2000-cycle limit, then read back. If the CPU times out, the readback is skipped and the testbench resets.

Limits: the readback covers only the first 16 data words, so a store to any other word is checked only through the ordered store stream. After the 20 programs, the supplied `gen_xbar` call sends random external-port traffic.

---

# 3. Assertions

## Assertion summary

| Assertion | Behavior checked | Sampled / disabled | Status |
| --- | --- | --- | --- |
| `NO_SIMULTANEOUS_READ_WRITE` | `w_en` and `r_en` are never high together | every clock, disabled during reset | Supplied with the scaffold, not mine |
| `NO_STORE_TO_DATA0` (3.1) | The CPU never writes data-SRAM word 0 | every clock, disabled during reset | Withdrawn |
| `NO_MEM_ACCESS_WHEN_IDLE` (3.2) | `dsram_en` is low while `cpu_active` is low and the external port is not requesting | every clock, disabled during reset | Kept, narrowed |
| `RESET_QUIESCES_CONTROL` (3.3) | After reset has been high for two clocks, `cpu_active` and `cpu_halted` are low | every clock, not disabled during reset | Kept, added after review |
| `HALT_RELEASES_CPU` (3.4) | After `halt_cpu` is asserted while `cpu_active` is high, `cpu_active` goes low within 2 clocks | every clock, disabled during reset | Kept, replaces 3.1 |

Every assertion reports through `assertion_fail`, so a violation is counted in the "Assertion failures" line of the final summary.

### 3.1 — `NO_STORE_TO_DATA0` (withdrawn)

In the initial plan I treated the Digital Design requirement that `data[0]` stays 0 as a rule for this testbench. It is not one. `init_memories()` fills data word 0 with a random value, and the scoreboard accepted a store to word 0 in random program 13 (0 mismatches). The assertion fired on that legal store at 707425 ns, so I removed it. It also fired on a deliberate `sw` to word 0 at 111005 ns, which shows it worked as written. Log: `evidence_NO_STORE_TO_DATA0.log`.

### 3.2 — `NO_MEM_ACCESS_WHEN_IDLE`

The CPU must not access the data SRAM while the external port owns it. The first version only checked `cpu_active`, and it fired on every external data-memory access, because the memory controller raises `dsram_en` for the external port. It now ignores cycles where the external port is requesting.

```systemverilog
NO_MEM_ACCESS_WHEN_IDLE:
  assert property (@(posedge cpu_if.clk) disable iff (rst)
    (!cpu_if.cpu_active && !cpu_if.r_en && !cpu_if.w_en) |-> (!cpu_if.dsram_en))
  else assertion_fail("CPU drove a data-SRAM access while not active");
```

### 3.3 — `RESET_QUIESCES_CONTROL` (added after review)

While reset is held, the control signals must be idle. Reset is synchronous, so the check starts once reset has been high on two consecutive clock edges. It has no `disable iff (rst)`, because it checks behavior during reset. My first version checked on the first edge and failed at 5 ns, because both signals are unknown before the first reset edge. Requiring that reset was also high on the previous edge (`rst_prev`) fixed it.

```systemverilog
RESET_QUIESCES_CONTROL:
  assert property (@(posedge cpu_if.clk)
    (cpu_if.reset && rst_prev) |-> (!cpu_if.cpu_active && !cpu_if.cpu_halted))
  else assertion_fail("Control signals not idle while reset was asserted");
```

### 3.4 — `HALT_RELEASES_CPU`

The README says an external halt returns the memories to the external port, and `chip_top.sv` drops the CPU enable when `halt_cpu_i` is high. The assertion checks that `cpu_active` goes low within two clocks.

```systemverilog
HALT_RELEASES_CPU:
  assert property (@(posedge cpu_if.clk) disable iff (rst)
    (cpu_if.halt_cpu && cpu_if.cpu_active) |-> ##[1:2] !cpu_if.cpu_active)
  else assertion_fail("cpu_active stayed high after an external halt request");
```

## Evidence that each assertion detects a violation

For each assertion I made one temporary change that should violate it, ran the suite, saved the log, and reverted the change. After every revert `git status` was clean and the suite passed with 0 assertion failures.

| Assertion | Temporary change | Result | Log |
| --- | --- | --- | --- |
| `NO_STORE_TO_DATA0` | added a test with `sw x0, 0(x0)` | fired at 111005 ns | `evidence_NO_STORE_TO_DATA0.log` |
| `NO_MEM_ACCESS_WHEN_IDLE` | default of `dsram_en_o` in `memory_controller.sv` set to 1 | fired at 55, 85, 105 and 125 ns, then on every clock | `evidence_NO_MEM_ACCESS.log` |
| `RESET_QUIESCES_CONTROL` | reset value of `halted_o` in `cpu_top.sv` set to 1 | fired at 15 ns | `evidence_RESET_QUIESCES.log` |
| `HALT_RELEASES_CPU` | `halt_cpu_i` removed from the enable logic in `chip_top.sv` line 53 | fired at 42455 ns | `evidence_HALT_RELEASES.log` |

---

# 4. Encrypted CPU Bug Hunt

All three bugs were found on bug-hunt variant 2 (username mrathod34). My own CPU passes every reproducer below. I added tests and fixed the testbench after the first random failures, so the same seeds no longer regenerate the original programs. The saved logs (`hunt_2_original.log`, `hunt_3_original.log`, `hunt_4_original.log`) hold the original programs. Every reproducer below is a directed test that still fails on the encrypted CPU with the final testbench.

## Bug 1: one store produces two data-SRAM writes

| Field | Evidence |
| --- | --- |
| Discovery command | `make bug_hunt SEED=random` |
| Numeric SVSEED | -1029823312 |
| Failing iteration | random_1 |
| First failure message | `[random_1] Store mismatch: expected [0x37] <- 0x0, got [0x109] <- 0x0` |
| Reproduction command | `make bug_hunt SEED=-1029823312` |
| Reproduces consistently? | Yes. Rerunning the same seed gave the same first failure. |

**Original failing program (random_1, 30 instructions, from `hunt_2_original.log`):**

```
[0] sub x1, x15, x4          [15] sw x3, 1696(x4)
[1] sw x2, 1060(x0)          [16] srl x6, x1, x2
[2] srl x5, x0, x2           [17] addi x1, x2, 0
[3] addi x6, x5, -2048       [18] beq x2, x8, 32
[4] sw x4, 220(x0)           [19] sub x21, x3, x5
[5] beq x4, x19, 40          [20] addi x0, x4, 1907
[6] sll x3, x2, x7           [21] sll x22, x7, x0
[7] sll x4, x3, x2           [22] sll x3, x0, x3
[8] addi x7, x6, 0           [23] sub x27, x0, x4
[9] add x16, x6, x3          [24] lw x6, 1572(x4)
[10] add x17, x0, x7         [25] beq x19, x5, 8
[11] sub x5, x6, x17         [26] lw x5, 32(x5)
[12] addi x0, x3, 0          [27] srl x18, x22, x6
[13] srl x7, x3, x0          [28] addi x2, x0, 896
[14] add x7, x14, x14        [29] ebreak
```

**Expected vs. actual**

| Instruction / event | Expected | Actual | Cycle/time |
| --- | --- | --- | --- |
| `sw x0, 4(x0)` | one data-SRAM write to word 1 | `dsram_write_en` high for two clock cycles with `dsram_addr` = 001 and data 0, so the monitor saw two stores | about 85,200 ns in the waveform run |
| Scoreboard | queue empty after the one store | `Unexpected CPU store to addr 0x1 with data 0x0` | 85515 ns |

**First architectural divergence:** the second data-SRAM write of the same `sw`. After it, the later stores in the original program were compared one position late, which produced the chain of store mismatches.

**Minimization.** Reducing the 30-instruction program gave:

```systemverilog
prog = '{
  asm_instr(.op(OP_SW), .rs1(0), .rs2(0), .imm(4)),   // sw x0, 4(x0)
  EBREAK_WORD
};
```

This is `min_one_store`. It fails on the encrypted CPU and passes on my CPU. I confirmed the minimum by reducing in steps (three stores, then one). I did not check whether the duplicate depends on the address, the data value or the base register.

**Waveform evidence:** `bug1_encrypted.png` (two-cycle write pulse) and `bug1_member.png` (one-cycle pulse), signals `dsram_en`, `dsram_write_en`, `dsram_addr`, `dsram_wdata`, `clk`.

**Conclusion**
- **Trigger:** a `sw` instruction. I tested only `sw x0, 4(x0)` and a three-store program.
- **Expected behavior:** one data-SRAM write per `sw`.
- **Observed behavior:** two consecutive writes with the same address and data.
- **Characterization:** the store write enable is high for two clock cycles instead of one (waveform). Not explained: the three-store test also reported `CPU halted before completing 2 expected stores`.

## Bug 2: beq takes the branch when the operands differ only above bit 7

| Field | Evidence |
| --- | --- |
| Discovery command | `make bug_hunt SEED=random` |
| Numeric SVSEED | -1494472679 |
| Failing iteration | random_13 |
| First failure message | `[random_13] read of register x3 returned 0x00000000, expected 0xdadc8511` |
| Reproduction command | `make bug_hunt SEED=-1494472679` |
| Reproduces consistently? | Yes for the directed reproducer below. The original random program no longer regenerates. |

**How it was found.** The random_13 failure above led to bug 3 (below). While reducing it I ran directed `beq` tests, and they showed this second trigger. I did not find a random program that shows only this trigger.

**Expected vs. actual**

| Instruction / event | Expected | Actual | Cycle/time |
| --- | --- | --- | --- |
| `beq x7, x6, 8` with x7 = 0 and x6 = 0x100 | not taken, so `addi x3, x0, 5` runs and x3 = 5 | branch taken, `addi x3` skipped, x3 = 0 | readback at 98555 ns |

**Minimization:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(8)),
  asm_instr(.op(OP_SLL),  .rd(6), .rs1(1), .rs2(2)),
  asm_instr(.op(OP_BEQ),  .rs1(7), .rs2(6), .imm(8)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
  EBREAK_WORD
};
```

This is `min_beq_bit8`. It fails on the encrypted CPU and passes on mine.

**Experiments separating the trigger from nearby possibilities.** x7 = 0 in every case, and x6 is the value shown.

| x6 | Result on the encrypted CPU |
| --- | --- |
| 1 and 2 (`min_beq_rs1zero`, `min_beq_nonzero`); 4, 16 and 128 (`min_beq_bit2`, `bit4`, `bit7`) | passes |
| 255 and 257 (`min_beq_imm255`, `min_beq_imm257`) | passes |
| 256 (`min_beq_bit8`, `min_beq_imm256`) | fails |
| 0x10000, 0x40000000 and 0x80000000 (`min_beq_bit16`, `bit30`, `highbit`) | fails |

**Waveform evidence:** `bug2_encrypted.png` (x3 reads 00000000) and `bug2_member.png` (x3 reads 00000005).

**Conclusion**
- **Trigger:** `beq` on two registers that differ only in bits above bit 7 (for example 0 and 0x100).
- **Expected behavior:** not taken, because the registers are not equal.
- **Observed behavior:** taken.
- **Characterization:** consistent with a comparison of only the low 8 bits. This is a hypothesis from the table above, because the RTL is protected.

## Bug 3: beq right after a lw reads the old value of the loaded register

| Field | Evidence |
| --- | --- |
| Discovery command | `make bug_hunt SEED=random` |
| Numeric SVSEED | -1494472679 (random_13) and 1345100999 (random_5) |
| Failing iteration | random_13 |
| First failure message | `[random_13] CPU halted before completing 1 expected stores` |
| Reproduction command | `make bug_hunt SEED=-1494472679` |
| Reproduces consistently? | Yes for the directed reproducer. The original random program no longer regenerates. |

**Original failing program (random_13, from `hunt_3_original.log`):**

```
[0] beq x1, x1, 24           [8] beq x7, x6, 28
[1] srl x3, x6, x4           [9] srl x20, x24, x4
[2] sw x1, 420(x1)           [10] lw x3, 900(x7)
[3] sw x5, 1984(x4)          [11] beq x17, x3, 8
[4] addi x1, x5, -2048       [12] sw x3, 1280(x3)
[5] sw x6, 1148(x1)          [13] add x5, x2, x3
[6] srl x0, x7, x6           [14] addi x30, x2, 0
[7] lw x6, 504(x3)           [15] ebreak
```

**Expected vs. actual**

| Instruction / event | Expected | Actual | Cycle/time |
| --- | --- | --- | --- |
| `lw x3, 900(x7)` then `beq x17, x3, 8` | loaded value is not 0, so the branch is not taken and the store at [12] runs | x3 ended at 0, no store was made, so the branch was taken | readback at 676095 ns |

**Minimization:**

```systemverilog
prog = '{
  asm_instr(.op(OP_LW),  .rd(6), .rs1(0), .imm(504)),
  asm_instr(.op(OP_BEQ), .rs1(7), .rs2(6), .imm(8)),
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(5)),
  EBREAK_WORD
};
```

This is `min_lwuse_beq`. x6 loaded `0x869afca3` and x7 = 0, so a correct CPU does not branch. The encrypted CPU did, and x3 ended at 0.

**Experiments separating the trigger from nearby possibilities**

| Test | Result on the encrypted CPU |
| --- | --- |
| `min_lw_gap_beq`: one unrelated `addi` between the `lw` and the `beq` | passes |
| `min_lwuse_stale_ne`: x6 was 5 before the `lw` | passes |
| `min_lwuse_stale_eq`: x6 and x7 both 5 before the `lw` | fails |
| `min_lwuse_add`: `add` right after the `lw` instead of `beq` | passes |
| `min_lw_pair`: two loads in a row | passes |

**Waveform evidence:** `bug3_encrypted.png` (x6 reads 869AFCA3, x3 reads 00000000) and `bug3_member.png` (x3 reads 00000005).

**Conclusion**
- **Trigger:** a `beq` immediately after a `lw` that loads one of its operand registers. The directed tests load the second operand. In random_5 the loaded register is the first operand, and I did not test that case separately.
- **Expected behavior:** the branch compares the loaded value.
- **Observed behavior:** the branch was taken, as if it had compared the register's value from before the load.
- **Characterization:** consistent with a stale read of the load target. The loaded value in the failing tests has a nonzero low byte, so bug 2 does not explain it. The `add` test passes, so the problem appears specific to the branch comparison.

---

# 5. Coverage

The coverage database from the full member suite gives 98.69% for `cpu_tb_top.dut` (1889 of 2019 items). That is above the 98% requirement. Screenshot: `coverage_final.png`.

| Metric for `dut` | Result |
| --- | --- |
| Block | 99.76% |
| Expression | 98.61% |
| Toggle | 96.84% |
| FSM | 100% |

The first measurement was already above 98%, so no test was added to close coverage. Running the planned directed tests afterwards did not change the figure.

---

# 6. Files in the archive

| File | What it shows |
| --- | --- |
| `simulation.log` | the member suite passing: 0 scoreboard mismatches, 0 driver timeouts, 0 assertion failures |
| `coverage_final.png` | IMC coverage for `cpu_tb_top.dut` |
| `bug1_encrypted.png`, `bug1_member.png` | bug 1 waveforms |
| `bug2_encrypted.png`, `bug2_member.png` | bug 2 waveforms |
| `bug3_encrypted.png`, `bug3_member.png` | bug 3 waveforms |
| `evidence_NO_STORE_TO_DATA0.log`, `evidence_NO_MEM_ACCESS.log`, `evidence_RESET_QUIESCES.log`, `evidence_HALT_RELEASES.log` | one log per assertion, taken with a temporary violation |
| `hunt_2_original.log`, `hunt_3_original.log`, `hunt_4_original.log` | the first random failures for the three bugs |
