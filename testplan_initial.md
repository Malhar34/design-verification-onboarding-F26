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
| Plan revision | Initial |
| Date | 2026-09-26 |

## Revision history

| Revision | Date | Changes |
| --- | --- | --- |
| Initial | 2026-09-26 | Initial planned tests |
| Final | TBD | |

---

## Verification strategy

The chip exposes three things an external observer can use: the crossbar port
(instruction SRAM, data SRAM, and a read-only register window), the
cpu_halted pulse, and the data-SRAM observation taps (dsram_en,
dsram_write_en, dsram_addr, dsram_wdata, dsram_rdata). Everything below
is written against those and not against CPU internals.

2 things here for my plan

**Final architectural state is not good enough evidence.** Reading registers and
data memory after halt tells you where the CPU ended up, not how it actually gets there.
The dSRAM taps let the monitor reconstruct every load and store as it happens,
so tests that care about which memory operations occurred (address scaling,
data[0] preservation, spurious writes) check the ordered stream rather than the end state.

**Tests are chosen by failure mode, not by opcode.** A checklist with one
friendly case per instruction proves almost nothing: an implementation can pass
`addi x1, x0, 5` while getting sign extension, shift masking, and address
scaling all wrong. Each test below names the specific incorrect implementation
it is designed to separate from the correct one. Where several instructions
share a failed mode, one test covers them. Where one instruction has several
distinct failed modes, it gets several tests.

The groupings are:

| Group | Tests | Failure modes targeted |
| --- | --- | --- |
| Value classes and limits | 1.1, 1.5–1.9 | sign extension, wraparound, shift-amount masking, logical vs arithmetic shift |
| Architectural invariants | 1.3, 1.4, 1.13, 1.15 | x0 semantics, `data[0]` preservation |
| Adjacent-instruction dependencies | 1.2, 1.26, 1.27 | results not committed before the next instruction reads them |
| Address translation | 1.10–1.12 | byte-vs-word scaling, negative offsets |
| Field aliasing | 1.14 | S-type immediate bits misread as a destination register |
| Control flow | 1.16–1.19 | branch direction, backward targets |
| Termination | 1.20–1.22 | halt stickiness, halt pulse shape, unsupported encodings |
| Ownership and port protocol | 1.23–1.25 | memory handoff, read-only window, unmapped window |

---

## Open questions I resolved before implementation

Recorded here deliberately. These affect how programs are written, and the
revision history should show when they were answered.

1. **Does `asm_instr`'s `imm` argument for `OP_BEQ` take a byte offset or a
   word offset?** Resolved 2026-09-26. `encode()` in `cpu_seq_item.svh`
   builds the B-type word as
   `{b_imm[12], b_imm[10:5], rs2, rs1, 3'b000, b_imm[4:1], b_imm[11], 7'b1100011}`,
   which is the standard RISC-V B-type layout with `imm[0]` implicit. The
   argument is therefore a byte offset relative to the branch
   instruction's own address. All branch programs in this plan are written on
   that basis and need no adjustment.
2. **What does `asm_instr(.op(OP_NOP))` encode to?** Resolved 2026-09-26.
   `encode()` has `default: word = '0;`, so an `OP_NOP` item produces
   `32'h0000_0000`. That word's opcode field is `7'b0000000`, which matches no
   supported instruction, so a correct decoder must take its default path and
   assert no write enables. Test 1.22 uses this word directly.
3. **What is the DUT's defined behavior for an external access with
   `addr[13:12] == 2'b11`?** `window_of()` returns `WIN_NONE`, but the README
   does not say whether the port returns `rready` with undefined data or never
   responds. Test 1.25 must be written against the actual contract.
4. **Does an external write attempted while `cpu_active` is high get dropped,
   queued, or corrupt memory?** The README says the port "is serviced only
   while the CPU is disabled," which does not by itself say what happens to a
   request made anyway. Test 1.23 covers this once it is is known.

---

# 1. Functional tests

## Functional-test summary

| Test ID | Test name | Functionality being tested | Expected result | Status |
| --- | --- | --- | --- | --- |
| 1.1 | `addi_imm_limits` | I-type immediate sign extension across its full range | Positive max, negative max, −1, and 0 all produce correct 32-bit values | Planned |
| 1.2 | `raw_dependency_chain` | A register written by instruction N is visible to instruction N+1 | Each result reflects the immediately preceding write | Planned |
| 1.3 | `x0_write_protection` | Writes targeting x0 are discarded | x0 reads 0 after both an `addi` and an `add` target it | Planned |
| 1.4 | `x0_source_reads_zero` | x0 reads as zero regardless of attempted writes | Arithmetic using x0 as a source behaves as if it were 0 | Planned |
| 1.5 | `add_value_classes` | Register-register add including 32-bit wraparound | Positive, mixed-sign, and overflow-wrap cases correct | Planned |
| 1.6 | `sub_value_classes` | Subtraction producing positive, nagative, and zero results | Negative reuslt is correct two's complement. Self subtract is 0 | Planned |
| 1.7 | `sll_shift_amount_masking` | Shift amount uses only the low 5 bits of rs2 | Shifts of 0, 31, 32, and 33 behave as 0, 31, 0, and 1 | Planned |
| 1.8 | `srl_is_logical` | Right shift fills with zeros, not the sign bit | 0x80000000 >> 1 yields 0x40000000, not 0xC0000000 | Planned |
| 1.9 | `shift_by_computed_amount` | Shift amount comes from a register, not an immediate | Shift by a runtime-computed value is correct | Planned |
| 1.10 | `sw_lw_roundtrip_distinct_words` | Stores and loads reach distinct memory words | Two values stored at different addresses read back independently | Planned |
| 1.11 | `mem_negative_offset` | Negative immediate offsets on loads and stores | A negative-offset access reaches the same word as the equivalent positive-offset access | Planned |
| 1.12 | `mem_byte_to_word_scaling` | Byte addresses are converted to word indices | Byte addresses 4, 8, 12 read preloaded words 1, 2, 3 | Planned |
| 1.13 | `data0_preservation` | `data[0]` is never written | `dmem[0]` is 0 after a program of stores elsewhere, and no observed store targets word 0 | Planned |
| 1.14 | `sw_does_not_write_rd` | S-type immediate bits in the rd field do not cause a register write | The register aliased by `imm[4:0]` is unchanged | Planned |
| 1.15 | `lw_into_x0` | A load targeting x0 is discarded | x0 reads 0 after `lw x0` of a nonzero value | Planned |
| 1.16 | `beq_taken_forward` | A taken branch redirects the PC forward | The skipped instruction leaves no trace | Planned |
| 1.17 | `beq_not_taken` | A not-taken branch falls through | The following instruction executes | Planned |
| 1.18 | `beq_backward_loop` | Negative branch offsets and repeated execution | A three-iteration loop produces the correct accumulator | Planned |
| 1.19 | `beq_equal_nonzero` | Equality between two nonzero registers | The branch is taken when rs1 == rs2 and neither is x0 | Planned |
| 1.20 | `ebreak_halt_pulse` | `ebreak` halts and pulses `cpu_halted` exactly once | One halt observation; prior results intact | Planned |
| 1.21 | `no_execution_past_ebreak` | Execution stops at `ebreak` | The instruction after `ebreak` leaves no trace | Planned |
| 1.22 | `unsupported_encoding_is_nop` | An unsupported encoding behaves as a no-op | PC advances; surrounding instructions unaffected | Planned |
| 1.23 | `ownership_handoff` | Memory ownership transfers at start and halt | External accesses succeed before start and after halt; `cpu_active` tracks the transition | Planned |
| 1.24 | `reg_window_read_only` | The register window rejects writes | A program-set register value survives an attempted external write | Planned |
| 1.25 | `unmapped_window` | Accesses to `addr[13:12] == 2'b11` | The port behaves the way detailed in its descriptoin without hanging the testbench | Planned |
| 1.26 | `store_then_load_same_word` | A load immediately after a store to the same word | The load returns the just-stored value | Planned |
| 1.27 | `branch_on_just_written_reg` | A branch whose condition regsiter was written by the previous instruction | The branch resolves on the new value | Planned |

---

## Functional-test details

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

**Final result:** _(to be filled after simulation)_

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

**Final result:** _(to be filled after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after the simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(to be filled after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

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

**Final result:** _(I will fill out after simulation)_

---

# 2. Constrained-random tests

## Instruction constraints

| Constraint | Provided, partial, or open | Behavior and purpose | Final implementation summary |
| --- | --- | --- | --- |
| `c_opcode` | Provided | Restricts `op` to the supported instruction set so generated programs contain only encodings the DUT and reference model both define. Without it, most random programs would be unsupported encodings and would exercise almost nothing. | No member change |
| `c_reg_bias` | Provided | Weights the register selection so a small set of registers is reused often. Uniform selection across 32 registers makes read-after-write dependencies rare; biasing creates them, which is where timing bugs appear. | No member change |
| `c_imm_range` | Partial | Supplied code constrains only `imm >= -2048`, leaving the upper end unbounded, so generated immediates can exceed what a 12-bit signed field can hold and `encode()` would silently truncate them. Completion must add `imm <= 2047`. Planned completion also biases toward the endpoints and zero so the sign-extension boundary in 1.1 is hit regularly by random stimulus rather than only by the directed test. | _(to be completed)_ |
| `c_mem_align` | Open | Must force load and store effective addresses to be word-aligned and within the 1024-word data SRAM. Requires constraining the base register value together with the offset, since the effective address is their sum. Planned approach: bias the base toward x0 and bound the offset to a multiple of 4 inside the memory range. | _(to be completed)_ |
| `c_imm_unused` | Provided | Forces the immediate field to a fixed value for instruction types that do not use it, so R-type programs are reproducible and the unused field cannot accidentally alias into a decoder path. | No member change |
| `c_branch_target` | Partial | Supplied code constrains `(imm % 4 == 0) && (imm >= 4)`, which forces every generated branch forward and word-aligned. The forward restriction is what the TODO means by "avoid loops," but it also means random stimulus can never exercise a negative branch offset — that path is covered only by directed test 1.18. What is still missing is an upper bound tying the offset to the remaining program length, so a forward target cannot land past the final `ebreak`. Planned completion bounds `imm` by `(prog_len - idx) * 4`. | _(to be completed)_ |
| `c_no_branch_at_end` | Provided | Prevents a branch in the final positions, where a forward target would fall outside the program. Keeps every generated program terminating at its `ebreak`. | No member change |
| `c_branch_taken_bias` | Open | Must make taken branches occur at a useful rate. Unconstrained random register values are almost never equal, so nearly every branch falls through and the taken path goes untested. Planned approach: force one branch operand to x0 with some probability and bias the other toward zero, so the taken path is exercised without eliminating the not-taken path. | _(to be completed)_ |

## External-port constraints

| Constraint | Provided, partial, or open | Behavior and purpose | Final implementation summary |
| --- | --- | --- | --- |
| `c_align` | Provided | Forces external addresses to be word-aligned, matching the port requirement that accesses are word-aligned. | No member change |
| `c_valid_window` | Partial | Must restrict `addr[13:12]` to mapped windows for ordinary traffic. Planned completion excludes `2'b11` from the default distribution while leaving a directed path for the unmapped-window test in 1.25. | _(to be completed)_ |
| `c_reg_read_only` | Provided | Prevents generating writes to the register window, which is read-only. Without it, random traffic would attempt illegal writes and the scoreboard would need to special-case them. | No member change |
| `c_data_corners` | Open | Must bias external write data toward corner values rather than uniformly random 32-bit numbers. Planned set: 0, 1, `0xFFFF_FFFF`, `0x8000_0000`, `0x7FFF_FFFF`, and values with a single bit set. These are the values most likely to expose sign, carry, and truncation bugs when later loaded and operated on. | _(I will complete this)_ |

## Random-program test

| Item | Plan |
| --- | --- |
| Number of programs per seed | 20 initially; raised if coverage closure requires it |
| Program-length range | 5 to 30 instructions plus a terminating `ebreak` |
| Information logged for reproduction | Numeric SVSEED, iteration index, and the complete generated program |

**Implementation outline:**

```systemverilog
// For each iteration:
//   1. Reset the chip and return all testbench signals to idle.
//   2. seqr.gen_program(...) to produce a randomized instruction sequence
//      terminated by EBREAK_WORD.
//   3. Print the iteration index and the full program before running, so a
//      failure is reproducible from the log alone.
//   4. Load the program and any randomized initial data memory through the
//      external port.
//   5. Load the same program and data into the reference model.
//   6. Pulse en_cpu and wait for the halt pulse with a bounded timeout.
//      On timeout: record a failure, reset, and skip readback so a hung
//      program does not generate misleading secondary mismatches.
//   7. Read the register window and data SRAM and compare against the
//      reference model prediction.
//   8. Compare the monitor's observed CPU_STORE stream against the reference
//      model's ordered store list.
```

Step 8 matters: comparing only final memory state would miss a store that wrote
the right value to the right place at the wrong time, or an extra store that was
later overwritten.

---

# 3. Assertions

## Assertion summary

| Assertion ID/name | Behavior checked | When it is sampled/disabled | Activating test |
| --- | --- | --- | --- |
| 3.1 / `NO_STORE_TO_DATA0` | The CPU never asserts a data-SRAM write to word address 0 | Every posedge clk, disabled during reset | 1.13, and every random program containing a store |
| 3.2 / `NO_MEM_ACCESS_WHEN_IDLE` | The CPU does not drive a data-SRAM access while `cpu_active` is low | Every posedge clk, disabled during reset | 1.23, and the boundary of every test |

### 3.1 — `NO_STORE_TO_DATA0`

**Timing requirement in words:** On any cycle where the CPU owns the memories
and asserts a data-SRAM write, the target word address must not be 0. This is a
same-cycle property with no temporal window: the violation is visible at the
moment the write is asserted, which is strictly stronger than checking
`dmem[0]` after the program ends, because a store of the value zero to word 0
would leave no trace in the final state.

```systemverilog
NO_STORE_TO_DATA0:
  assert property (@(posedge clk) disable iff (reset)
    (cpu_active && dsram_en && dsram_write_en) |-> (dsram_addr != 10'd0))
  else assertion_fail("CPU asserted a data-SRAM write to word address 0");
```

**Evidence that it detects a violation:** _(planned)_ Temporarily add a program
containing `sw x1, 0(x0)`, confirm the assertion fires with the cycle recorded
in the log, capture the waveform showing `dsram_write_en` high with
`dsram_addr == 0`, then revert.

### 3.2 — `NO_MEM_ACCESS_WHEN_IDLE`

**Timing requirement in words:** While `cpu_active` is low, the CPU must not
drive a data-SRAM access. Ownership belongs to the external port during that
time, and a CPU access would corrupt testbench-written data or return data the
CPU was not entitled to read. Also a same-cycle property.

```systemverilog
NO_MEM_ACCESS_WHEN_IDLE:
  assert property (@(posedge clk) disable iff (reset)
    (!cpu_active) |-> (!dsram_en))
  else assertion_fail("CPU drove a data-SRAM access while not active");
```

**Evidence that it detects a violation:** _(planned)_ Temporarily force
`cpu_active` low for one cycle mid-program, confirm the assertion fires, retain
the log and waveform, then revert.

**Note on a third candidate:** A bounded-response assertion on the external
port — every `r_en` to a mapped window must be answered by `rready` within N
cycles — would cover the protocol timing rather than the CPU. It is deferred
until open question 3 fixes N and the unmapped-window contract.

---

# 4. Encrypted CPU Bug Hunt

Not started. This stage runs after the member suite passes and coverage closes.
Per the README, each bug must first be found through constrained-random
stimulus, not written as a directed test in advance, so no bug hypotheses are
recorded here.

## Random discovery

| Field | Evidence |
| --- | --- |
| Discovery command | `make bug_hunt SEED=random` |
| Numeric SVSEED | _(to be recorded)_ |
| Failing iteration | _(to be recorded)_ |
| First failure message | _(to be recorded)_ |
| Reproduction command | `make bug_hunt SEED=________` |
| Reproduces consistently? | _(to be recorded)_ |

**Original failing program:**
```systemverilog
prog = '{
  // Paste original generated sequence
  EBREAK_WORD
};
```

## Expected vs. actual

| Instruction / event | Expected | Actual | Cycle/time |
| --- | --- | --- | --- |
| | | | |

**First architectural divergence:** _(to be recorded)_

## Minimization

**Minimized reproducer:**
```systemverilog
prog = '{
  // Smallest sequence that still fails
  EBREAK_WORD
};
```

## Waveform evidence

_(screenshot to be added)_

## Conclusion

**Trigger:** _(to be recorded)_

**Expected behavior:** _(to be recorded)_

**Observed behavior:** _(to be recorded)_

**Behavioral characterization:** _(to be recorded)_

---

## Planned minimization method

Recorded now so the approach is not improvised under time pressure:

1. Keep the first reproducible failing seed and iteration untouched as the
   primary record.
2. Bisect the failing program by halving the instruction sequence, keeping the
   half that still fails.
3. Once no further instruction can be removed, vary one operand at a time to
   separate the trigger from coincidental context — for example, whether the
   failure depends on a specific register number, a specific immediate value,
   or only on the instruction pair being adjacent.
4. Construct a directed test that reproduces the failure deterministically, and
   confirm it passes against the member CPU. A reproducer that also fails on a
   known-good CPU indicates a testbench defect rather than a DUT bug.
