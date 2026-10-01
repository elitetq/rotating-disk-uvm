# Requirements, observations and findings

Tests, sequences, assertions and log messages in this repo refer to short IDs such as
`R-PWM-2`, `O-CLAMP-1` or `F-001`. For example, an assertion failure prints
`Failed R-PWM-2 assertion.`. This file lists what each ID means.

## How the IDs work

| Prefix | Kind | Meaning |
|---|---|---|
| `R-<BLOCK>-n` | **Requirement** | A promise the design must keep. Tests and assertions check these. |
| `O-<BLOCK>-n` | **Observation** | Something notable found by reading the RTL. Each one gets a verdict once investigated. |
| `F-nnn` | **Finding** | An issue confirmed during verification that was not already listed as an observation. |

Verdicts are one of:

- **bug**: the design is wrong.
- **limitation**: the design is right, but its behaviour is bounded, and that is documented.
- **out of spec**: the input was outside the declared legal range.

A blank verdict means the item has not been investigated yet.

The requirement and observation IDs use different abbreviations for the same block:

| Block | Requirement prefix | Observation prefix | RTL |
|---|---|---|---|
| PWM generator | `R-PWM` | `O-PWM` | `pwm_n_bit` |
| Magnitude clamp | `R-CLP` | `O-CLAMP` | `magnitude_clamp` |
| Quadrature decoder | `R-QUD` | `O-QUAD` | `decoder_to_32_bit` and its submodules |
| Controller | `R-CTL` | `O-CTRL` | `controller` |
| Full loop | `R-SYS` | — | `prop_ctrl_pwm` |
| LED bar, 7-segment display | — | `O-LED`, `O-7SEG` | `led_status`, `status_7seg` |
| Clock divider | — | `O-DIV` | `clock_div` |

---

## Requirements

**Source** says where each requirement comes from:

- **RTL**: what the code evidently intends.
- **Derived**: worked out from the RTL.
- **Design intent**: what the design is for.
- **Declared** or **decided**: a range or behaviour I chose, because the RTL alone does not
  settle it.
- **TBD**: still open.

### `pwm_n_bit`

| ID | Requirement | Source |
|---|---|---|
| R-PWM-1 | Output period is exactly `2**BITS` cycles of `clk` | RTL |
| R-PWM-2 | High time is `(duty > THRESHOLD) ? duty + 1 : 0` cycles per period | derived |
| R-PWM-3 | Output is low for every `duty <= THRESHOLD` (the deadband) | design intent |
| R-PWM-4 | Maximum duty is **100%**, reached at `duty = 2**BITS − 1` | decided |
| R-PWM-5 | Asserting `reset` forces the counter to 0 and the output low within 1 cycle | RTL |
| R-PWM-6 | Legal parameters: `BITS ∈ [1, 16]`, `THRESHOLD ∈ [0, 2**BITS − 1]` | TBD |
| R-PWM-7 | Minimum non-zero duty is `(THRESHOLD + 2) / 2**BITS`; 0% is reachable only through the deadband | derived, TBD |

R-PWM-4 is the requirement that turned a quirk into a bug. The original RTL topped out at
`240/256 = 93.75%`. Once 100% was written down as a requirement, that became a defect. The
fix is recorded in [`rtl/PROVENANCE.md`](rtl/PROVENANCE.md). R-PWM-7 is the smaller offset
the fix left behind (see O-PWM-1).

### `magnitude_clamp`

| ID | Requirement | Source |
|---|---|---|
| R-CLP-1 | `dir` is 1 if and only if `value < 0`; `value == 0` gives `dir = 0` | RTL |
| R-CLP-2 | `clamped_value` equals `min(\|value\|, CLAMP_VAL)` | RTL |
| R-CLP-3 | The result is correct for `value = 32'h8000_0000` (the most negative 32-bit number) | edge case |
| R-CLP-4 | The block is combinational: outputs settle within one delta of an input change | RTL |
| R-CLP-5 | Legal parameter range: `CLAMP_VAL ∈ [1, 2**31 − 1]`, meaning `CLAMP_VAL` fits in a signed 32-bit integer | **declared** |

**About R-CLP-5.** `CLAMP_VAL` is assumed to fit in a signed 32-bit integer.
- **Why 32 bits:** the RTL declares it `parameter int`, and the testbench carries it the same
  way. It is passed through `uvm_config_db#(int)`, the golden model takes it as an `int`,
  and `clamp_if` carries `clamped_value` on a 32-bit bus.
- **Why `2**31 − 1` and not `2**32 − 1`:** `int` is signed. A larger value would go negative,
  and the RTL's unsigned comparison (O-CLAMP-4) would then break the saturation.
- **Why at least 1:** see O-CLAMP-3.

A configuration outside this range is out of spec, not a bug.

### `decoder_to_32_bit`

| ID | Requirement | Source |
|---|---|---|
| R-QUD-1 | One count per full quadrature cycle, with the sign matching the direction of rotation | RTL |
| R-QUD-2 | 4 `clk` edges from a channel edge to the `count` update | derived |
| R-QUD-3 | Dither (back-and-forth jitter) at the `00` detent produces net-zero displacement | design intent |
| R-QUD-4 | Dither at `01`, `10` or `11` produces no pulses | derived |
| R-QUD-5 | `pulse` is high for exactly one cycle per counted step | RTL |
| R-QUD-6 | Counts correctly up to a maximum quadrature cycle rate (the value is still TBD; see O-QUAD-1) | TBD |
| R-QUD-7 | `reset` zeroes `count` and clears all locks | RTL |
| R-QUD-8 | `count` is stable while `pulse` is low | RTL |

### `controller`

| ID | Requirement | Source |
|---|---|---|
| R-CTL-1 | `error = position − ref_position`, where `ref_position` is `reference` delayed by one clock | RTL |
| R-CTL-2 | `error_scaled` equals the signed product `error × k`, truncated to 32 bits | RTL |
| R-CTL-3 | The truncated result equals the true signed product whenever `\|error × k\| < 2**31` | derived |
| R-CTL-4 | Legal range for `k` (the value is still TBD; see O-CTRL-1) | TBD |
| R-CTL-5 | Behaviour when `\|error × k\| >= 2**31`: bug or out of spec (still TBD) | TBD |
| R-CTL-6 | `reset` forces `ref_position` to 0 | RTL |

### `prop_ctrl_pwm` (the full loop)

| ID | Requirement | Source |
|---|---|---|
| R-SYS-1 | `motor_in1` and `motor_in2` are always complementary | RTL |
| R-SYS-2 | `motor_in1 = 1` when the disk must turn toward a greater reference (`error < 0`) | design intent |
| R-SYS-3 | `pwm_cmp` equals `min(\|error_scaled\|, 2**BITS − 1)` | derived |
| R-SYS-4 | With zero error and `duty` inside the deadband, `motor_en` stays low | derived |
| R-SYS-5 | From any starting error, moving the encoder toward the reference shrinks `pwm_cmp` steadily to zero | design intent |
| R-SYS-6 | The loop is closed: `position` affects `error` | regression guard |

R-SYS-6 sounds trivial, but the design failed it before verification started (F-000). It is
listed so that no later refactor can break it without a test noticing.

---

## Observations

| ID | Module | Observation | Verdict |
|---|---|---|---|
| O-PWM-1 | `pwm_n_bit` | Duty map is offset by one (`duty` gives `duty + 1` high cycles); 0% is reachable only through the deadband. The original RTL could not reach 100%; that was fixed. | original: **bug**, fixed; what remains: **limitation** |
| O-PWM-2 | `pwm_n_bit` | Deadband: every `duty <= THRESHOLD` gives a constantly low output | **limitation** (intended) |
| O-PWM-3 | `top_module` | `THRESHOLD` units disagree with `status_7seg` (180 vs 360 degrees per 512 ticks) | **bug** (provisional, needs a hardware check) |
| O-PWM-4 | `pwm_n_bit` | A negative `THRESHOLD` makes the unsigned compare fail, so the output is stuck low | **out of spec** |
| O-PWM-5 | `pwm_n_bit` | Changing `duty` mid-period produces a runt, extended or double pulse | **limitation** |
| O-CLAMP-1 | `magnitude_clamp` | `INT_MIN` is handled correctly, but only because the negated value is read back as unsigned | |
| O-CLAMP-2 | `magnitude_clamp` | The output width `$clog2(CLAMP_VAL+1)` always holds `CLAMP_VAL`, so nothing is truncated | |
| O-CLAMP-3 | `magnitude_clamp` | `CLAMP_VAL = 0` gives an illegal output width | |
| O-CLAMP-4 | `magnitude_clamp` | `value_abs > CLAMP_VAL` is an unsigned compare: harmless for positive `CLAMP_VAL`, wrong for negative | |
| O-QUAD-1 | `first_value_priority` | Counts are lost above about 12.5 M quadrature cycles/s | |
| O-QUAD-2 | `first_value_priority` | The lock becomes visible two edges late | |
| O-QUAD-3 | `first_value_priority` | The `pulse <= 0` default sits above the reset branch. This is legal, but a refactor could easily break it. | |
| O-QUAD-4 | `synchronizer` | No reset, so its outputs are `x` for the first two clocks | |
| O-QUAD-5 | `first_value_priority` | `dir` keeps the last counted direction between pulses; it means nothing while `pulse` is low | |
| O-QUAD-6 | `directional_counter` | No saturation; the count wraps at ±2³¹ | |
| O-CTRL-1 | `controller` | Overflow in `error × k` flips `dir`, so the motor runs away from the target | |
| O-CTRL-2 | `controller` | The upper 32 bits of `error_scaled_int` are meaningless | |
| O-CTRL-3 | `controller` | `ref_position` is registered, so `error` lags `reference` by one clock | |
| O-LED-1 | `led_status` | The LED bar reads only `pwm_cmp[7:0]`, so it aliases when `BITS > 8` | |
| O-7SEG-1 | `status_7seg` | The degree display wraps above 1023 ticks | |
| O-DIV-1 | `clock_div` | `TICKS < 2` fails elaboration (or the clock never toggles) | |
| O-DIV-2 | `clock_div` | The Xilinx `BUFG` primitive does not exist in plain simulation; replaced by `tb/common/bufg_stub.sv` | |

---

## Findings

| ID | Module | Finding | Verdict |
|---|---|---|---|
| F-000 | `controller` / `prop_ctrl_pwm` | Open control loop: `position` was shadowed by an internal signal and left unconnected | **bug**, fixed before verification ([`rtl/PROVENANCE.md`](rtl/PROVENANCE.md)) |
| F-001 | `pwm_n_bit` | `pwm_out` goes high during reset when `duty > THRESHOLD` (breaks R-PWM-5) | **bug**, fixed locally; found by `pwm_reset_test` |
