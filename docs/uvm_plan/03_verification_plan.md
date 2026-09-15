# Verification Plan

Copy this into `docs/verification_plan.md` in your repo and fill it in **before** you write
tests. Yes, before.

---

## Why this document exists

Writing random tests and watching them pass is not verification. Verification is answering
"what does this design promise, and have I checked all of it?" — and you cannot answer that
without first writing down the promise.

Three concrete things a vplan buys you on this project:

1. **It settles bug-versus-limitation arguments.** Upstream `pwm_n_bit` could not reach
   100% duty (O-PWM-1). Is that a defect? Unanswerable until someone writes "the PWM shall
   be capable of 0–100% duty" or "0–95%". You were the someone: **R-PWM-4 was resolved in
   favour of full scale**, and `rtl/pwm_n_bit.sv` now carries the fix (`rtl/PROVENANCE.md`
   §2). Keep this entry — the point is not that you happened to be right, it is that the
   question was undecidable until the requirement existed.
2. **It stops you from testing what is easy instead of what matters.** Left to instinct, you
   will write six `pwm_n_bit` tests and one quadrature test. The interesting failures are all
   in the quadrature decoder and the control loop.
3. **It is the thing an interviewer asks for.** "How did you know when you were done?" has a
   good answer only if you wrote one down in advance.

**Format note:** a vplan is a living document. Fill in the status columns as you go; the
version you commit at the end, with everything closed out and the unreachable items argued,
is the artifact.

---

## 1. Scope

### In scope

| DUT | Level | Phase |
|---|---|:--:|
| `pwm_n_bit` | block | A |
| `magnitude_clamp` | block | B |
| `decoder_to_32_bit` (incl. `first_value_priority`, `synchronizer`, `directional_counter`) | block | C |
| `prop_ctrl_pwm` | subsystem | D |

### Out of scope, and why

| Not verified | Reason |
|---|---|
| `enel453_lab_initializer` | Button/ROM sequencing; 5 ms debounce windows make it a poor fit for randomized simulation and it adds no new verification technique. |
| `debounce` | Same. Trivially checkable by directed test; already covered by the existing `debounce_tb`. |
| `status_7seg` | Display formatting. Observed inside the Phase D DUT but not driven to closure. |
| `led_status` / `bar_encoder` | Same — observed at Phase D only. One known defect recorded (O-LED-1). |
| `top_module` | Full-chip integration; existing `top_module_tb` covers the smoke path. |
| Gate-level / timing simulation | Behavioural only. No SDF back-annotation. |

State this in your README too. Scoping honestly reads as competence; implying full coverage
you do not have reads as the opposite.

### Modelling assumptions

| # | Assumption | Impact |
|---|---|---|
| M1 | `BUFG` replaced by a wire (`bufg_stub.sv`) | No global-buffer routing delay modelled. Zero functional impact. |
| M2 | Phase D runs at `PWM_CLK_FREQ_HZ = 98_000` instead of 490 | Changes only the divider ratio; one test at production parameters confirms. |
| M3 | Encoder channels driven with ideal (glitch-free) edges except where a test explicitly injects dither | Contact bounce on the encoder is not modelled. |
| M4 | `clk` is a clean 100 MHz with no jitter | Behavioural sim. |

---

## 2. Design requirements

**Fill this in from the lab specification and your own design intent.** These are the
promises the testbench checks. Where you genuinely do not know the intended value, write
`TBD` and resolve it — either from the lab handout or by measuring the hardware.

### `pwm_n_bit`

| ID | Requirement | Source | Status |
|---|---|---|---|
| R-PWM-1 | Output period shall be exactly `2**BITS` cycles of `clk` | RTL intent | |
| R-PWM-2 | High time shall be `(duty > THRESHOLD) ? duty + 1 : 0` cycles per period | derived, DUT §1 | |
| R-PWM-3 | Output shall be low for all `duty <= THRESHOLD` (deadband) | design intent | |
| R-PWM-4 | Maximum achievable duty fraction shall be **100%**, at `duty = 2**BITS − 1` | **decided** — see below | |
| R-PWM-7 | Minimum achievable *non-zero* duty fraction shall be `(THRESHOLD + 2) / 2**BITS`; 0% is reachable only through the deadband | derived, O-PWM-1 | |
| R-PWM-5 | Asserting `reset` shall force the counter to 0 and the output low within 1 cycle | RTL | |
| R-PWM-6 | Legal parameter range: `BITS ∈ [1,16]`, `THRESHOLD ∈ [0, 2**BITS−1]` | **you declare** | |

> **R-PWM-4 is the one that mattered, and it is now closed.** The answer written down was
> "100% is required". Upstream RTL topped out at `240/256 = 93.75%`, so that made it a bug,
> and the fix — `Q <= duty` instead of `Q < duty`, shifting the whole mapping by one — is
> applied in `rtl/pwm_n_bit.sv` and recorded in `rtl/PROVENANCE.md` §2. The same change also
> moved the deadband test from `Q > THRESHOLD` to `duty > THRESHOLD`, which is why R-PWM-3's
> boundary moved by one and the pulse is now contiguous from `Q = 0`.
>
> R-PWM-7 is what the fix left behind: the map is `duty → duty + 1`, so the first non-zero
> output is a `16/256 = 6.25%` step at `THRESHOLD = 14`. Decide whether that step is
> acceptable and write the argument down — that is the same exercise R-PWM-4 was, on the
> residual. **Keep the history of R-PWM-4 visible rather than editing it away.** "Here is a
> requirement I wrote, the bug it exposed, the fix, and the smaller finding the fix left"
> is the single most useful paragraph this document will contain.

### `magnitude_clamp`

| ID | Requirement | Source | Status |
|---|---|---|---|
| R-CLP-1 | `dir` shall be 1 iff `value < 0`; `value == 0` shall give `dir = 0` | RTL | |
| R-CLP-2 | `clamped_value` shall equal `min(\|value\|, CLAMP_VAL)` | RTL | |
| R-CLP-3 | Shall be correct for `value = 32'h8000_0000` (INT_MIN) | edge case | |
| R-CLP-4 | Combinational: output settles within one delta of an input change | RTL | |
| R-CLP-5 | Legal parameter range: `CLAMP_VAL ∈ [1, 2**31−1]` | **you declare** | |

### `decoder_to_32_bit`

| ID | Requirement | Source | Status |
|---|---|---|---|
| R-QUD-1 | One count per full quadrature cycle, sign matching rotation direction | DUT §3 | |
| R-QUD-2 | Latency from a channel edge to `count` update shall be 4 `clk` edges | derived | |
| R-QUD-3 | Dither at the `00` detent shall produce net-zero displacement | design intent | |
| R-QUD-4 | Dither at `01`, `10` or `11` shall produce no pulses | derived | |
| R-QUD-5 | `pulse` shall be high for exactly one cycle per counted step | RTL | |
| R-QUD-6 | Shall count correctly for quadrature cycle rates up to **TBD** | **you declare** — see O-QUAD-1 | |
| R-QUD-7 | `reset` shall zero `count` and clear all locks | RTL | |
| R-QUD-8 | `count` shall be stable when `pulse` is low | RTL | |

> R-QUD-6 is your best finding opportunity. The arithmetic in DUT §3 predicts a knee at
> ~12.5 M quadrature cycles/s. Measure it, compare, and state the margin against the
> physical maximum of your motor.

### `controller` (inside `prop_ctrl_pwm`)

| ID | Requirement | Source | Status |
|---|---|---|---|
| R-CTL-1 | `error = position − ref_position`, where `ref_position` is `reference` delayed one clock | RTL | |
| R-CTL-2 | `error_scaled` shall equal the signed product `error × k` truncated to 32 bits | RTL | |
| R-CTL-3 | The truncated result shall equal the true signed product whenever `\|error × k\| < 2**31` | derived, DUT §4 | |
| R-CTL-4 | Legal range for `k`: **TBD** — see O-CTRL-1 | **you declare** | |
| R-CTL-5 | Behaviour when `\|error × k\| >= 2**31`: **TBD** — bug, or out of spec? | **you decide** | |
| R-CTL-6 | `reset` shall force `ref_position` to 0 | RTL | |

> R-CTL-4/5 are the judgement call of the project. Options in DUT §4. Whichever you pick,
> write the argument in one paragraph — that paragraph is what separates this from a
> student exercise.

### `prop_ctrl_pwm` (subsystem)

| ID | Requirement | Source | Status |
|---|---|---|---|
| R-SYS-1 | `motor_in1` and `motor_in2` shall always be complementary | RTL | |
| R-SYS-2 | `motor_in1 = 1` when the disk must rotate toward a greater reference (`error < 0`) | design intent | |
| R-SYS-3 | `pwm_cmp` shall equal `min(\|error_scaled\|, 2**BITS − 1)` | derived | |
| R-SYS-4 | With zero error and `duty` inside the deadband, `motor_en` shall be constantly low | derived | |
| R-SYS-5 | From any initial error, driving the encoder toward the reference shall reduce `pwm_cmp` monotonically to zero | design intent | |
| R-SYS-6 | The loop shall be closed: `position` shall influence `error` | **regression guard for the Step 0 bug** | |

> R-SYS-6 is deliberately trivial-sounding. It is also the requirement your design failed
> until Step 0. Add it explicitly so no future refactor can break it silently — that is what
> a regression suite is *for*.

---

## 3. Test plan

One row per test. `Type`: **D**irected, **CR** constrained-random, **A**ssertion-only.

### Phase A — `pwm_n_bit`

| Test | Type | Requirements | Stimulus | Checks |
|---|:--:|---|---|---|
| `pwm_smoke_test` | D | R-PWM-1,2 | 3 fixed duties, whole periods | scoreboard |
| `pwm_random_test` | CR | R-PWM-1,2 | uniform `duty`, ≥50 items | scoreboard + SVA |
| `pwm_corner_test` | CR | R-PWM-2,3,4,7 | `duty ∈ {0,1,T,T±1,max,max−1}` weighted | scoreboard + SVA; `duty = max` must give `high_cycles == 2**BITS` |
| `pwm_duty_change_test` | D | R-PWM-5 | change `duty` mid-period | observe and record; no scoreboard claim |
| `pwm_reset_test` | D | R-PWM-5 | assert reset at random offsets in a period | counter zeroed, output low |

### Phase B — `magnitude_clamp`

| Test | Type | Requirements | Stimulus | Checks |
|---|:--:|---|---|---|
| `clamp_smoke_test` | D | R-CLP-1,2 | 7 hand-picked values | scoreboard |
| `clamp_random_test` | CR | R-CLP-1,2 | uniform 32-bit | scoreboard + SVA |
| `clamp_corner_test` | CR | R-CLP-2,3 | `dist`-weighted corners | scoreboard + SVA |
| — run all three at `CLAMP_VAL` = 100 / 255 / 4095 | | R-CLP-5 | parameter override | all pass unchanged |

### Phase C — `decoder_to_32_bit`

| Test | Type | Requirements | Stimulus | Checks |
|---|:--:|---|---|---|
| `quad_smoke_test` | D | R-QUD-1,2 | one forward cycle | count +1, latency = 4 |
| `quad_forward_test` | CR | R-QUD-1 | 1–500 forward steps, random rate | scoreboard |
| `quad_reverse_test` | CR | R-QUD-1 | as above, reverse | scoreboard |
| `quad_reversal_test` | CR | R-QUD-1,5 | direction flips mid-run | scoreboard |
| `quad_dither_test` | D | R-QUD-3,4 | 100 rattles at each of the 4 states | net displacement 0 at `00`; zero pulses elsewhere |
| `quad_fast_test` | CR | R-QUD-6 | step period swept down to the knee | find where counts are dropped; compare to prediction |
| `quad_reset_test` | D | R-QUD-7 | reset mid-run | count zeroed, locks cleared, counting resumes |
| `quad_random_test` | CR | all | composing sequence, random mix | scoreboard + SVA |

### Phase D — `prop_ctrl_pwm`

| Test | Type | Requirements | Stimulus | Checks |
|---|:--:|---|---|---|
| `ctrl_smoke_test` | D | R-SYS-1,2,6 | fixed reference, position 0 | direction pins, `pwm_cmp` saturated |
| `ctrl_random_test` | CR | R-CTL-1,2,3; R-SYS-3 | random reference, position, `k` in legal range | full-chain scoreboard |
| `ctrl_convergence_test` | CR | R-SYS-5,6 | drive the encoder toward the reference | `pwm_cmp` monotonically → 0; `motor_en` stops |
| `ctrl_gain_sweep_test` | CR | R-CTL-3,4,5 | `k` swept past the overflow threshold | overflow assertion; record behaviour |
| `ctrl_reset_test` | D | R-CTL-6 | reset mid-motion | clean restart |
| `ctrl_slow_test` | D | M2 | production `PWM_CLK_FREQ_HZ = 490`, one seed | same checks pass |

---

## 4. Coverage plan

Coverage is the evidence that your random stimulus actually reached the interesting states.
A test that passes but covers nothing has proved nothing.

### Functional coverage

| Covergroup | Coverpoints | Crosses | Goal |
|---|---|---|:--:|
| `cg_pwm_duty` | `duty`: `0`, `1`, `[2:T]`, `T+1`, `T+2`, `[T+3 : max−2]`, `max−1`, `max` | — | 100% |
| `cg_clamp_value` | `sign` (neg/zero/pos); `magnitude` band (0, 1, `<CLAMP`, `==CLAMP`, `>CLAMP`, INT_MIN) | `sign × magnitude`, `ignore_bins` for zero×negative | 100% |
| `cg_quad_state` | `{a_sync, b_sync}` current state (4 bins) | transition coverage: all 16 `state => state` | 100% or argued |
| `cg_quad_rate` | `step_period_clks` bands: 2, 3–4, 5–16, 17–256, >256 | `× direction` | 100% |
| `cg_quad_dither` | dither injected at each of the 4 states | — | 100% |
| `cg_ctrl_error` | `error` sign; magnitude bands (0, 1, `<clamp`, `==clamp`, `>clamp`) | `× k_band × saturated` | 90% |
| `cg_ctrl_k` | `k`: 1, 2, small, mid, near-overflow, overflowing | — | 100% |
| `cg_ctrl_converged` | a bin that only fills when `error` actually reaches 0 during a test | — | 100% |

> `cg_ctrl_converged` is worth calling out. It is a single-bin covergroup whose only job is
> to prove that at least one test drove the system all the way to zero error. Without it,
> a suite can pass every check while never once exercising the state the design exists to
> reach. Cheap to write, and exactly the kind of thing that impresses in a review.

### Code coverage

Optional. If XSim's code coverage works cleanly for you, collect line and branch coverage on
the RTL and report it. If the flow proves fragile, skip it and say so — functional coverage
is the more meaningful number for a design this size, and knowing the difference between the
two is itself worth being able to explain.

### Closure rules

For every unfilled bin at the end, exactly one of:

- **Add stimulus** — write the sequence or constraint that reaches it.
- **Argue unreachable** — with a specific reason. "Cannot occur because `up_lock` is set by
  the immediately preceding transition" is an argument. "Probably impossible" is not.
- **Exclude with `ignore_bins`** — and say why in a comment next to it.

An unexplained hole is the only unacceptable outcome.

---

## 5. Assertion plan

Assertions attached with `bind`, so the RTL is never edited. See `tutorials/T8`.

| File | Property | Requirement |
|---|---|---|
| `pwm_n_bit_sva.sv` | `pwm_out == ((duty > THRESHOLD) && (Q <= duty))` every cycle | R-PWM-2 |
| | `Q` increments by 1 every cycle unless reset | R-PWM-1 |
| | reset ⇒ `Q == 0` next cycle | R-PWM-5 |
| | parameter guard: `THRESHOLD` in range | R-PWM-6 |
| `magnitude_clamp_sva.sv` | `clamped_value <= CLAMP_VAL` always | R-CLP-2 |
| | `dir == (value < 0)` | R-CLP-1 |
| | parameter guard: `CLAMP_VAL >= 1` | R-CLP-5 |
| `first_value_priority_sva.sv` | `pulse` never high two consecutive cycles | R-QUD-5 |
| | `pulse` ⇒ next cycle `count` changed by exactly ±1 | R-QUD-1 |
| | `!pulse` ⇒ next cycle `count` unchanged | R-QUD-8 |
| | `dir` stable while `pulse` low | O-QUAD-5 |
| `controller_sva.sv` | `error_scaled == (error * k)[31:0]` | R-CTL-2 |
| | overflow flag: `\|error * k\| >= 2**31` never occurs (or is reported) | R-CTL-4/5 |
| `prop_ctrl_pwm_sva.sv` | `motor_in1 != motor_in2` always | R-SYS-1 |
| | `pwm_cmp <= 2**BITS − 1` always | R-SYS-3 |
| | `error == 0` ⇒ `pwm_cmp == 0` | R-SYS-4 |
| `clock_div_sva.sv` | parameter guard: `TICKS >= 2` | O-DIV-1 |

All of them need `disable iff (reset)` — and the quadrature ones additionally need a settle
window for O-QUAD-4's `x` propagation.

---

## 6. Completion criteria

The project is done when **all** of these are true:

- [ ] Every requirement in §2 has status `PASS`, `FAIL (documented)`, or `NOT VERIFIED (out of scope, documented)`. No blanks.
- [ ] Every test in §3 passes across at least 10 seeds.
- [ ] Every covergroup in §4 meets its goal, or every hole has a written argument.
- [ ] Every assertion in §5 is bound and has been observed to fire at least once against
      deliberately broken RTL. *An assertion you have never seen fail is not evidence.*
- [ ] Every observation in the DUT register (`02_design_under_test.md` §7) has a verdict and
      a one-line argument.
- [ ] `python3 sim/regress.py` exits 0 from a clean checkout.
- [ ] The README explains the architecture, how to run it, what is covered, and what is not.

---

## 7. Status summary

Update at each phase gate.

| Phase | Tests passing | Coverage | Assertions bound | Notes |
|---|---|---|---|---|
| A | | | | |
| B | | | | |
| C | | | | |
| D | | | | |

**Bugs found:** _(link to `docs/results.md`)_

**Requirements marked TBD still open:** R-PWM-6, R-PWM-7, R-CLP-5, R-QUD-6, R-CTL-4, R-CTL-5

**Closed:** R-PWM-4 — decided as 100%; upstream RTL did not meet it; fixed in
`rtl/pwm_n_bit.sv` (`rtl/PROVENANCE.md` §2).
