# Fall 2026 DV Onboarding Test Plan

<!--
Make two copies of this template:
  1. testplan_initial.md, submitted before implementing tests.
  2. testplan_final.md, updated after implementation and coverage closure.

Keep the initial copy unchanged after review. HTML comments are editing
instructions and disappear from rendered Markdown.
-->
## NOTE: THIS IS A TEMPLATE FOR YOU TO FOLLOW. THIS IS **NOT** A COMPREHENSIVE TESTPLAN. YOU NEED TO EXTEND IT.
## Document information

| Field | Value |
| --- | --- |
| Verification engineer | Name, Discord username, GT username |
| Plan revision | Initial / Final |
| Date | YYYY-MM-DD |

### Revision history

| Revision | Date | Changes |
| --- | --- | --- |
| Initial | YYYY-MM-DD | Initial planned tests |
| Final | YYYY-MM-DD | <!-- Tests or constraints added after debugging and coverage review --> |

## 1. Functional tests

<!--
Plan tests for the CPU functionality supported by this onboarding. Organize
related behavior together. Include both individual instruction behavior and
multi-instruction sequences where ordering or dependencies matter.

Add as many rows and detailed test records as needed. Do not put every CPU
operation into one large program: each failure should identify a reasonably
small area to debug.
-->

### Functional-test summary

| Test ID | Test name | Functionality being tested | Expected result | Status |
| --- | --- | --- | --- | --- |
| 1.1 | `test_name` |  |  | Planned |
| 1.2 |  |  |  | Planned |
| 1.3 |  |  |  | Planned |

### Functional-test details

<!-- Duplicate this complete record for every functional test. -->

### 1.1 — `test_name`

**Functionality:** <!-- State exactly what CPU behavior this test checks. -->

**Initial state:**

- Registers: <!-- Usually reset state unless the program establishes another value. -->
- Data memory: <!-- List relevant initialized word addresses and values, or write “none.” -->
- Other setup: <!-- Reset, program timeout, number of words to read back, etc. -->

**Program:**

<!-- Use the same representation that will be placed in run_member_directed_tests(). -->

```systemverilog
prog = '{
  // asm_instr(.op(...), .rd(...), .rs1(...), .rs2(...), .imm(...)),
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x__` | `32'h________` |  |
| `dmem[__]` | `32'h________` |  |

**Pass criteria:** <!-- Include halt/timeout behavior and any state that must remain unchanged. -->

**Final result:** <!-- Complete in testplan_final.md: pass/fail and useful log or waveform reference. -->

## 2. Constrained-random tests

### Instruction constraints

<!--
Explain the provided constraints, then record how the partial and open
constraints are completed. State what each constraint permits, excludes, or
biases and why the resulting programs remain useful and terminating.
-->

| Constraint | Provided, partial, or open | Behavior and purpose | Final implementation summary |
| --- | --- | --- | --- |
| `c_opcode` | Provided |  | No member change |
| `c_reg_bias` | Provided |  | No member change |
| `c_imm_range` | Partial |  |  |
| `c_mem_align` | Open |  |  |
| `c_imm_unused` | Provided |  | No member change |
| `c_branch_target` | Partial |  |  |
| `c_no_branch_at_end` | Provided |  | No member change |
| `c_branch_taken_bias` | Open |  |  |

### External-port constraints

| Constraint | Provided, partial, or open | Behavior and purpose | Final implementation summary |
| --- | --- | --- | --- |
| `c_align` | Provided |  | No member change |
| `c_valid_window` | Partial |  |  |
| `c_reg_read_only` | Provided |  | No member change |
| `c_data_corners` | Open |  |  |

### Random-program test

| Item | Plan |
| --- | --- |
| Number of programs per seed |  |
| Program-length range |  |
| Information logged for reproduction | Numeric `SVSEED`, iteration, and complete generated program |

**Implementation outline:**

```systemverilog
// Write the intended loop and lifecycle using seqr.gen_program(...).
```

## 3. Assertions

<!--
Plan at least two assertions in addition to the supplied example. Write the
timing rule in English first. In the final plan, include the exact SVA and
evidence from a temporary violation proving that the assertion can fire.
-->

### Assertion summary

| Assertion ID/name | Behavior checked | When it is sampled/disabled | Activating test |
| --- | --- | --- | --- |
| 4.1 / `PROPERTY_NAME` |  |  |  |
| 4.2 / `PROPERTY_NAME` |  |  |  |

### 4.1 — `PROPERTY_NAME`

**Timing requirement in words:**

```systemverilog
PROPERTY_NAME:
  assert property (@(posedge clk) disable iff (rst)
    /* property expression */)
  else assertion_fail("descriptive failure message");
```

**Evidence that it detects a violation:** <!-- Temporary change, failing log/waveform, and confirmation after reverting it. -->

### 4.2 — `PROPERTY_NAME`

**Timing requirement in words:**

```systemverilog
PROPERTY_NAME:
  assert property (@(posedge clk) disable iff (rst)
    /* property expression */)
  else assertion_fail("descriptive failure message");
```

**Evidence that it detects a violation:**

## 4. Encrypted CPU Bug Hunt

### Random discovery

| Field                    | Evidence                      |
| ------------------------ | ----------------------------- |
| Discovery command        | `make bug_hunt SEED=random`   |
| Numeric `SVSEED`         |                               |
| Failing iteration        |                               |
| First failure message    |                               |
| Reproduction command     | `make bug_hunt SEED=________` |
| Reproduces consistently? | Yes / No                      |

**Original failing program:**

```systemverilog
prog = '{
  // Paste original generated sequence
  EBREAK_WORD
};
```

### Expected vs. actual

| Instruction / event | Expected | Actual | Cycle/time |
| ------------------- | -------- | ------ | ---------- |
|                     |          |        |            |

**First architectural divergence:**

<!-- State the first register, memory, or control-flow result that becomes incorrect. -->

### Minimization

**Minimized reproducer:**

```systemverilog
prog = '{
  // Smallest sequence that still fails
  EBREAK_WORD
};
```

### Waveform evidence

Include a screenshot showing the offending instruction and the first incorrect architectural result.

### Conclusion

**Trigger:**

<!-- Smallest condition that causes the failure. -->

**Expected behavior:**

<!-- ISA-correct behavior. -->

**Observed behavior:**

<!-- What the encrypted CPU does instead. -->

**Behavioral characterization:**

<!-- One precise sentence. Do not speculate about hidden RTL. -->

