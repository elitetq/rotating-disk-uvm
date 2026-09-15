# Phase D — `prop_ctrl_pwm`

**Goal:** reuse the Phase A and Phase C agents **without modifying them**, model the whole
control law, and check a closed loop.

**Time:** 1.5–2 weeks. **Prerequisite:** Phase C gate passed.

This is the payoff phase. If your agents were built properly they drop straight in. If they
were not, you will find out here — and that discovery is itself the lesson.

**Read first:** `tutorials/T4` (config_db, because you now have three agents to configure)
and `02_design_under_test.md` §4 and §6.

---

## The DUT

```systemverilog
module prop_ctrl_pwm #(parameter int BITS = 12,
                       parameter int THRESHOLD = 0,
                       parameter int PWM_CLK_FREQ_HZ = 490) (
    input  logic              clk, reset,
    input  logic signed [31:0] reference, k,
    input  logic              ch_a, ch_b,
    output logic [15:0]       led,
    output logic [6:0]        seg,
    output logic [3:0]        an,
    output logic              motor_en, motor_in1, motor_in2
);
```

The chain (all combinational off two registered values, except the final PWM):

```
  ch_a/ch_b ─► decoder_to_32_bit ─► position ──┐
                                                ├─► error = position − ref_position
  reference ─► [1 clk register] ─► ref_position ┘         │
                                                          ▼
                              error_scaled = (error × k)[31:0]
                                                          │
                                                          ▼
                          magnitude_clamp(2**BITS − 1) ─► pwm_cmp, dir
                                          │                │
                                          │                ├─► motor_in1 = dir
                                          │                └─► motor_in2 = ~dir
                                          ▼
                             pwm_n_bit(clk_divd) ─────────────► motor_en
```

**Note the clock domains.** Everything down to `pwm_cmp` is on `clk`. `pwm_n_bit` runs on
`clk_divd`, produced by `clock_div` (which contains a `BUFG` — use your stub).

---

## Step D1 — Make it simulate in finite time

At production parameters this DUT takes 204 800 `clk` cycles per PWM period
(`02_design_under_test.md` §6). Ten periods across fifty seeds is an overnight run.

### The override

```systemverilog
module tb_ctrl_top #(
  parameter int BITS            = 8,
  parameter int THRESHOLD       = 14,
  parameter int PWM_CLK_FREQ_HZ = 98_000     // sim value; production is 490
);
```

Arithmetic, from `02_design_under_test.md` §6:

| | Production | Simulation |
|---|---:|---:|
| `PWM_CLK_FREQ_HZ` | 490 | 98 000 |
| `clock_div` target | 124 950 Hz | 24 990 000 Hz |
| `TICKS` | 400 | **2** (still ≥ 2 — satisfies O-DIV-1) |
| `clk_divd` | 125 kHz | 25 MHz |
| PWM period | 204 800 clk ≈ 2.048 ms | **1024 clk ≈ 10.24 µs** |

**200× faster, and the DUT logic is untouched.** Only the divider ratio changes; nothing you
are actually checking depends on it.

Run production parameters once, in `ctrl_slow_test`, with a single seed:

```bash
make PHASE=ctrl TEST=ctrl_slow_test PARAM="PWM_CLK_FREQ_HZ=490" SEED=1 run
```

### Why this is a legitimate technique, and where it stops being one

You are allowed to change a parameter for speed **only when it does not change the behaviour
under test**. Here it changes how many `clk` cycles fit in a `clk_divd` cycle — a ratio the
PWM logic never observes. It would **not** be legitimate to shrink `BITS`, because that
changes the duty resolution and the clamp value, which are exactly what you are checking.

Being able to state that distinction is the point. Record M2 in your verification plan's
assumptions table, and say in `docs/results.md` that the production configuration was
confirmed by a separate run.

### Gate D1

Elaborate at sim parameters and confirm in the waveform that `motor_en` has a ~1024-cycle
period. Also confirm the `TICKS >= 2` assertion does not fire — if you picked a
`PWM_CLK_FREQ_HZ` that drives `TICKS` to 1, elaboration fails outright (O-DIV-1) and now you
know why that guard was worth writing.

---

## Step D2 — The `ctrl_agent`

Small: it drives `reference` and `k`, and monitors them so the scoreboard knows what was
applied and when.

```systemverilog
class ctrl_item extends uvm_sequence_item;
  rand bit signed [31:0] reference;
  rand bit        [31:0] k;
  rand int unsigned      hold_clks;    // how long to hold this setting

  `uvm_object_utils_begin(ctrl_item)
    `uvm_field_int(reference, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(k,         UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(hold_clks, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "ctrl_item"); super.new(name); endfunction

  // TODO(you): constraints.
  //   c_reference : keep it in a physically plausible range. The encoder gives
  //                 512 ticks/rev, so ±2048 is ±4 revolutions — plenty.
  //                 A separate sequence can go wider to probe O-7SEG-1.
  //
  //   c_k         : THE DECISION. See 02_design_under_test.md §4 (O-CTRL-1).
  //                 Whatever legal range you declared as R-CTL-4, constrain to
  //                 it here — and write a SEPARATE unconstrained sequence for
  //                 ctrl_gain_sweep_test that deliberately violates it.
  //                 Constraining the ordinary tests to the legal range is not
  //                 hiding the bug; it is the difference between "the design
  //                 fails in spec" and "the design fails out of spec", which
  //                 are completely different findings.
  //
  //   c_hold      : long enough that the PWM monitor sees at least one whole
  //                 period at a stable command. With sim parameters that is
  //                 ≥ 1024 clk. This constraint is load-bearing — see D5.
endclass
```

The driver is trivial: drive both values through the clocking block, hold for `hold_clks`.
The monitor publishes `(reference, k)` whenever either changes.

---

## Step D3 — The environment, and reuse

```systemverilog
class ctrl_env extends uvm_env;

  `uvm_component_utils(ctrl_env)

  quad_agent      quad;      // ACTIVE  — from Phase C, unmodified
  ctrl_agent      ctrl;      // ACTIVE  — new, small
  pwm_agent       pwm;       // PASSIVE — from Phase A, unmodified
  ctrl_predictor  pred;
  ctrl_scoreboard sb;
  ctrl_coverage   cov;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    uvm_config_db#(uvm_active_passive_enum)::set(this, "quad", "is_active", UVM_ACTIVE);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "ctrl", "is_active", UVM_ACTIVE);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "pwm",  "is_active", UVM_PASSIVE);

    // ... create all six components ...
  endfunction

endclass
```

**`pwm` is passive.** Nothing drives `duty` — the DUT's own `magnitude_clamp` does. The agent
exists only to reuse the Phase A monitor's duty-measuring logic on `motor_en`. This is the
concrete payoff of building the active/passive split in Phase A, and it is worth a sentence
in your README.

### Three virtual interfaces, three config_db keys

Each agent needs its own. Watch the paths:

```systemverilog
  uvm_config_db#(virtual quad_if)::set(null, "*.quad*", "vif", quad_vif);
  uvm_config_db#(virtual ctrl_if)::set(null, "*.ctrl*", "vif", ctrl_vif);
  uvm_config_db#(virtual pwm_if )::set(null, "*.pwm*",  "vif", pwm_vif);
```

The types differ, so `"*"` would actually work here — but it will not the day you have two
agents of the same type, and getting into the habit now costs nothing. `tutorials/T4` covers
the wildcard rules and the failure modes.

### Gate D3

All three monitors publishing, printing to a temporary subscriber, no scoreboard yet. Confirm
in the log that quadrature pulses, reference changes and PWM periods all show up.

---

## Step D4 — The control-law golden model

Add to `dut_pkg`:

```systemverilog
  // ------------------------------------------------------------------
  // controller  (02_design_under_test.md §4)
  //
  //   error_scaled = (error * k) truncated to 32 bits.
  //
  //   The RTL performs an UNSIGNED multiply (k is unsigned), but truncation
  //   to 32 bits makes that equivalent to the signed product modulo 2**32.
  //   Model it the same way: compute in 64 bits, take the low 32, and
  //   reinterpret as signed.
  // ------------------------------------------------------------------
  function automatic bit signed [31:0] expected_error_scaled(
      input bit signed [31:0] error,
      input bit        [31:0] k);
    // TODO(you): two lines. Do NOT "fix" the truncation in the model —
    //            the model's job is to predict what the RTL does, not what
    //            you wish it did.
  endfunction

  // True when the true product does not fit in 32 signed bits (O-CTRL-1).
  function automatic bit error_scaled_overflows(
      input bit signed [31:0] error,
      input bit        [31:0] k);
    // TODO(you): compute the true product in 64 bits and compare against
    //            the signed 32-bit range.
  endfunction

  // ------------------------------------------------------------------
  // The whole prop_ctrl_pwm command chain, in one function.
  // ------------------------------------------------------------------
  typedef struct {
    bit signed [31:0] error;
    bit signed [31:0] error_scaled;
    bit        [31:0] pwm_cmp;
    bit               dir;
    bit               overflow;
  } ctrl_pred_t;

  function automatic ctrl_pred_t expected_ctrl(
      input bit signed [31:0] position,
      input bit signed [31:0] ref_position,   // already delayed one clock
      input bit        [31:0] k,
      input int               bits);
    // TODO(you): chain expected_error_scaled -> expected_clamp.
    //            Reuse the Phase B function; do not write a second clamp model.
    //            One model, verified once, used everywhere — that is the whole
    //            reason dut_pkg is a package of pure functions.
  endfunction
```

**`ref_position` is delayed one clock (O-CTRL-3), `position` is not.** Model that in the
predictor, not in this function — keep `dut_pkg` free of timing.

---

## Step D5 — The predictor and scoreboard

The hardest single component in the project. Read this whole section before writing code.

### The structural question: what is observable?

| Signal | Observable? | How to check it |
|---|---|---|
| `motor_in1`, `motor_in2` | **Yes**, real outputs | Compare against predicted `dir` every clock. Black box. |
| `motor_en` | **Yes**, real output | Measure duty over a PWM period; compare against `expected_pwm_high(pwm_cmp, THRESHOLD)`. Black box, but only valid when the command is stationary. |
| `led` | **Yes**, real output | `bar_encoder` is lossy (log meter), so this confirms the magnitude band, not the exact value. Useful cross-check; also how you demonstrate O-LED-1. |
| `pwm_cmp`, `error_scaled`, `position` | **No**, internal | Probe, or infer. See below. |

### Where `position` comes from — the important idea

You do **not** need to probe `position`. The Phase C scoreboard already maintains an expected
count from the quadrature monitor's pulse stream, and Phase C **proved that model matches the
DUT** across twenty seeds and full transition coverage.

So Phase D can *trust* it: subscribe to the quad monitor, maintain the same running count,
and use it as `position`.

That is verification reuse working as intended — you verified the decoder at block level, so
at subsystem level you get to treat it as a known-good model instead of re-verifying it. It
is also the honest answer to "how do you avoid re-verifying everything at every level?", and
worth being able to say out loud.

If the Phase D scoreboard starts failing on `position`, that means the block-level proof did
not hold at subsystem level — which is itself an extremely interesting result and exactly
what integration testing is for.

### The predictor

Separate the *model* from the *comparison*. The predictor holds the timing; the scoreboard
holds the verdict.

```systemverilog
class ctrl_predictor extends uvm_component;

  `uvm_component_utils(ctrl_predictor)

  // Inputs, from the two active agents
  uvm_analysis_imp_decl(_quad)      // see tutorials/T6 — lets one component
  uvm_analysis_imp_decl(_ctrl)      // have two differently-typed imps

  uvm_analysis_imp_quad #(quad_obs, ctrl_predictor) quad_imp;
  uvm_analysis_imp_ctrl #(ctrl_obs, ctrl_predictor) ctrl_imp;

  // Output, to the scoreboard
  uvm_analysis_port #(ctrl_expected) ap;

  virtual ctrl_if vif;         // for the clock and reset only

  bit signed [31:0] position_model;
  bit signed [31:0] reference_applied;
  bit signed [31:0] ref_position_model;    // reference delayed one clock
  bit        [31:0] k_applied;

  function void write_quad(quad_obs obs);
    // TODO(you): position_model += obs.net_displacement;
  endfunction

  function void write_ctrl(ctrl_obs obs);
    // TODO(you): latch reference_applied and k_applied
  endfunction

  task run_phase(uvm_phase phase);
    // TODO(you): every clk edge —
    //   1. ref_position_model <= reference_applied;   // the DUT's 1-clk register
    //   2. pred = dut_pkg::expected_ctrl(position_model, ref_position_model,
    //                                    k_applied, bits);
    //   3. publish it on ap
    //
    // Cycle alignment is the whole difficulty here. Two things to get right:
    //
    //   (a) The DUT's ref_position updates on the same edge your model does.
    //       Use a nonblocking assignment so the ordering matches.
    //
    //   (b) position_model is updated by write_quad(), which fires when the
    //       MONITOR sees a pulse — one clock BEFORE the DUT's counter updates
    //       (Phase C, §C5). Either delay the model by one clock here or have
    //       the monitor publish one clock later. Pick one, write it in a
    //       comment, and be consistent.
    //
    // If your scoreboard reports a mismatch on exactly the cycle after every
    // reference change or every encoder pulse, it is (a) or (b). It is almost
    // never the RTL.
  endtask

endclass
```

### The scoreboard

```systemverilog
class ctrl_scoreboard extends uvm_scoreboard;

  // From the predictor
  uvm_analysis_imp_exp #(ctrl_expected, ctrl_scoreboard) exp_imp;
  // From the passive PWM monitor
  uvm_analysis_imp_pwm #(pwm_obs, ctrl_scoreboard) pwm_imp;

  // TODO(you): three independent checks.
  //
  //   CHECK 1 — direction, every clock, black box.
  //     motor_in1 == predicted dir, motor_in2 == ~predicted dir.
  //     Cheap, cycle-accurate, and it is the check that would have caught the
  //     Step 0 position bug. (R-SYS-1, R-SYS-2, R-SYS-6)
  //
  //   CHECK 2 — effort, per PWM period, black box.
  //     Compare the pwm_obs high-cycle count against
  //     expected_pwm_high(predicted pwm_cmp, THRESHOLD).
  //     ONLY VALID IF the command was stable for the whole period — which is
  //     why ctrl_item.hold_clks has a lower bound (D2) and why the encoder
  //     must be quiet during the measurement. Have the scoreboard TRACK
  //     stability and skip the check when the command moved mid-period,
  //     counting the skips. If you skip more than you check, your sequences
  //     are wrong.
  //
  //   CHECK 3 — LED band, every clock, black box.
  //     led == expected_led(predicted pwm_cmp[7:0], predicted dir).
  //     Lossy but free, and it is how you demonstrate O-LED-1: run at
  //     BITS=12 and watch this check fail when pwm_cmp exceeds 255.
  //
  // TODO(you): report_phase — counts for each check, plus the skip count for
  //            CHECK 2, plus the usual uvm_error if nothing was checked.
endclass
```

### On CHECK 2's stability requirement

This is a real, common verification problem and worth understanding rather than working
around. A duty-cycle measurement is an *average over a window*; if the input changed during
the window, the average has no single correct value. Three ways to handle it, all used in
practice:

1. **Constrain the stimulus** so the command holds still across measurement windows. Simple,
   and the right default. It is why `hold_clks` has a lower bound.
2. **Detect and skip** — measure anyway, notice the command moved, discard the sample and
   count the discard. Necessary once you have a closed-loop test where the command
   legitimately moves.
3. **Probe `pwm_cmp` directly** and check the instantaneous relation with an assertion
   instead of a windowed measurement. Cycle-accurate, but white box.

Do 1 and 2 in the scoreboard, and 3 as an assertion. Together they cover both the stationary
and moving cases, which is exactly the argument you want to be able to make.

---

## Step D6 — The closed-loop convergence test

Every test so far has been open-loop: apply stimulus, check the response. This one closes the
loop, and it is the test that actually proves the design does its job.

```systemverilog
class ctrl_convergence_seq extends uvm_sequence;
  `uvm_object_utils(ctrl_convergence_seq)

  task body();
    // TODO(you):
    //   1. Set a random reference (say ±512 ticks) and k = 1, position at 0.
    //   2. Wait for the command to settle. Record pwm_cmp (or infer it from
    //      the measured duty).
    //   3. Loop:
    //        drive ONE quadrature step in the direction that reduces |error|
    //          — which direction is that? motor_in1 tells you: the DUT is
    //            already saying which way it wants to go. Use it. That is what
    //            makes this closed loop rather than a scripted trajectory.
    //        wait for the command to settle (a few clocks)
    //        assert the new |pwm_cmp| <= the previous one
    //      until error reaches zero.
    //   4. Assert motor_en stays low once error is zero and the command is
    //      inside the deadband.
    //
    // This needs sequences on TWO sequencers — quad and ctrl. Options:
    //   (a) a virtual sequence with a virtual sequencer holding handles to
    //       both, or
    //   (b) one sequence with handles to both sequencers passed in via
    //       config_db or set directly by the test.
    //
    // (a) is the textbook UVM answer and worth building ONCE so you can say
    // you have. (b) is less code. If you build (a), write down what it bought
    // you over (b) for THIS environment — "not much, at this scale" is a
    // perfectly good and quite mature answer.
  endtask
endclass
```

**Why monotonic decrease and not just "reaches zero":** a test that only checks the endpoint
would pass on a design that overshoots wildly and oscillates back. Checking the trajectory
checks the control law, not just the arithmetic. It is also the check that will catch a sign
error anywhere in the chain, immediately.

### Gate D6

Converges from at least five random starting errors, in both directions, with the monotonic
property holding throughout. This is the test to show someone when they ask what the project
does.

---

## Step D7 — The `k` overflow investigation

The judgement call of the project. `02_design_under_test.md` §4 (O-CTRL-1) has the analysis:
once `|error| × k ≥ 2³¹` the truncated product wraps, the sign bit flips, and the motor
drives **away** from the target at full effort.

### The experiment

```systemverilog
class ctrl_gain_sweep_seq extends uvm_sequence;
  task body();
    // TODO(you):
    //   Fix error at a known value (say 512 ticks — one revolution).
    //   Sweep k across the boundary: 2**22 - 1, 2**22, 2**22 + 1, and well beyond.
    //   At each point, record the predicted and observed dir and pwm_cmp.
    //
    //   Predicted boundary for |error| = 512:  k = 2**31 / 512 = 4_194_304.
    //   Confirm the flip happens exactly there. If it does not, work out why
    //   before writing anything down.
  endtask
endclass
```

### The write-up

This is what actually goes in your results document. Something like:

> **O-CTRL-1 — proportional gain overflow.** `controller` computes
> `error_scaled = (error × k)[31:0]`. For `|error| × k ≥ 2³¹` the truncation wraps and the
> sign bit inverts, so `magnitude_clamp` reports the opposite direction and `prop_ctrl_pwm`
> drives the motor away from the target at saturated effort — a runaway, not a degradation.
> Measured boundary at `|error| = 512` ticks: `k = 4 194 304`, matching prediction.
>
> `top_module` hardcodes `K = 1`, so the deployed configuration is unaffected, and `k` has
> no documented legal range.
>
> **Verdict: limitation, with a recommendation.** Declared legal range `k ∈ [1, 4096]`
> (R-CTL-4), which bounds `|error × k|` below 2³¹ for any error within ±512 k ticks.
> Constrained random tests to that range; `ctrl_gain_sweep_test` characterizes behaviour
> outside it. **Recommended fix:** saturate rather than truncate —
> `error_scaled = clamp(error × k, −2³¹, 2³¹−1)` — costing one comparator and a mux, which
> converts a runaway into a saturation.

That paragraph is worth more than another hundred lines of testbench. It shows you found
something, quantified it, decided what it meant, and proposed a fix with a cost estimate.

### Gate D7

The boundary is measured and matches prediction; the verdict and recommendation are written;
the assertion is in place either way.

---

## Step D8 — Production parameters

```bash
make PHASE=ctrl TEST=ctrl_slow_test PARAM="PWM_CLK_FREQ_HZ=490" SEED=1 run
```

One seed, one test, at the real configuration. It will take minutes rather than seconds.
Confirm the same checks pass. Record it in `docs/results.md` — this is what discharges
assumption M2.

---

## Phase D gate

- [ ] All six tests pass across ten seeds at simulation parameters.
- [ ] `ctrl_slow_test` passes at production parameters.
- [ ] Convergence test converges from five random starting errors with the monotonic
      property holding.
- [ ] `k` overflow boundary measured, matching prediction, with a written verdict.
- [ ] O-LED-1 demonstrated at `BITS = 12` and recorded.
- [ ] The Phase A and Phase C agents were reused **without modification** — or you recorded
      exactly what had to change and why.
- [ ] Committed.

### Explain these out loud

1. Why is the `pwm_agent` passive here, and what would go wrong if it were active?
2. Where does your scoreboard get `position` from, and why is it legitimate not to probe it?
3. Your duty-cycle check is invalid when the command moves mid-period. How did you handle
   that, and why is skipping a sample not the same as ignoring a failure?
4. You changed `PWM_CLK_FREQ_HZ` for simulation. Why is that legitimate, and name a
   parameter it would **not** be legitimate to change.
5. The convergence test checks monotonic decrease rather than just reaching zero. Why?
6. Is the `k` overflow a bug? Defend your answer.
