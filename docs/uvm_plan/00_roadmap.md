# Roadmap

The working checklist. Every task has an **acceptance gate** — a command you run and an
output you look for. If the gate does not pass, do not move on; the next phase assumes the
last one is solid.

Commit at every gate. Suggested message format: `phase-a: monitor publishing duty on analysis port`.

---

## Step 0 — Baseline and toolchain (½ day)

### 0.1 Fix the `position` bug in your RTL

Your synthesis log (`enel441_453_lab.runs/synth_1/runme.log`) already reports this:

```
WARNING: [Synth 8-11121] redeclaration of ANSI port 'position' is not allowed   controller.sv:34
WARNING: [Synth 8-7071]  port 'position' of module 'controller' is unconnected
                         for instance 'CONTROLLER'                             prop_ctrl_pwm.sv:56
WARNING: [Synth 8-7023]  instance 'CONTROLLER' has 6 connections declared, but only 5 given
```

**What happened.** On `main`, `controller` instantiated `decoder_to_32_bit` internally. On
`mvp_changes` you hoisted the decoder up into `prop_ctrl_pwm` — the right refactor — but two
things got left behind:

- `controller.sv` still declares `position` as an internal signal *and* as an input port.
- `prop_ctrl_pwm.sv` never connects `.position(...)` when instantiating `controller`.

So `controller` computes `error = position - ref_position` with `position` tied off. The
proportional loop is **open**: the error is `-ref_position` forever, regardless of where the
disk actually is.

- [ ] **`controller.sv`, line 34** — remove `position` from the internal declaration:

  ```systemverilog
  // before
  logic signed [31:0]            position, ref_position, error;
  // after
  logic signed [31:0]            ref_position, error;
  ```

- [ ] **`prop_ctrl_pwm.sv`, line 56** — add the missing connection. The `position` net
  already exists in that module and is driven by the `DECODER` instance:

  ```systemverilog
  controller #(.BITS(BITS)) CONTROLLER (
      .clk(clk),
      .reset(reset),
      .reference(reference),
      .position(position),        // <-- add this
      .k(k),
      .error_scaled(error_scaled)
  );
  ```

**Gate:** re-run synthesis. All three warnings above are gone.

### 0.2 Green baseline on the existing testbenches

- [ ] Run `prop_ctrl_pwm_tb` in Vivado. Expect `ALL CHECKS PASSED`.
- [ ] Run `top_module_tb` in Vivado. Expect `ALL CHECKS PASSED`. This one covers ~25 ms of
      board time and takes a while.

> Worth doing *before* the fix too, if you want to see it: `top_module_tb` Check 4 ("motor_en
> stopped once the target was reached") is exactly the check an open loop fails. Run it
> broken, watch Check 4 fail, then fix and watch it pass. Twenty minutes, and it is the
> clearest possible demonstration of why you are about to spend six weeks on this.

**Gate:** both testbenches print `ALL CHECKS PASSED`. Commit the fix to `mvp_changes`.

### 0.3 Create the repo

- [ ] `mkdir ~/rotating-disk-uvm && cd ~/rotating-disk-uvm && git init`
- [ ] Create the directory skeleton (layout in `01_toolchain.md`).
- [ ] Copy the RTL into `rtl/`. Write `rtl/PROVENANCE.md` naming the source repo, branch and
      commit hash you copied from, and the date. Future-you will want to know whether the
      vendored copy has drifted.
- [ ] Copy the Makefile, filelists and `.gitignore` from `01_toolchain.md`.

**Gate:** `git log` has one commit, `tree` matches the layout in `01_toolchain.md`.

### 0.4 Prove UVM runs on XSim

Do not skip this. Debugging "does my toolchain support UVM" and "is my driver wired up"
at the same time is miserable.

- [ ] Write `tb/top/tb_hello.sv` — the smoke test in `01_toolchain.md`. One test class, one
      `uvm_info`, nothing else.
- [ ] Compile, elaborate and run it.

**Gate:** you see the UVM banner (`UVM_INFO ... UVM-1.2`), your `Hello` message, and a
report summary ending `UVM_ERROR : 0` / `UVM_FATAL : 0`.

### 0.5 Decide the BUFG strategy

`clock_div` instantiates a Xilinx `BUFG` primitive, which does not exist in a plain
SystemVerilog compile. It only bites at Phase D, but decide now.

- [ ] Write `tb/common/bufg_stub.sv` (two lines — see `01_toolchain.md`) and add it to the
      Phase D filelist. **Recommended:** portable, keeps the flow simulator-agnostic.
- [ ] Note the substitution in your README so nobody mistakes it for silicon behaviour.

**Gate:** noted in `docs/results.md` under "Modelling assumptions".

---

## Phase A — `pwm_n_bit` (~1 week)

The goal is **not** to verify `pwm_n_bit` thoroughly. It is to get every UVM moving part in
place on a DUT so simple that when something breaks, it is obviously the testbench.

Build in this order. Simulate after every single step.

- [ ] **A1 — Interface + TB top.** `tb/common/pwm_if.sv` with a clocking block; `tb_pwm_top`
      generating clock and reset and instantiating the DUT. Hardcode `duty` in an `initial`
      block. *Gate:* waveform shows `pwm_out` pulsing at the duty you set.
- [ ] **A2 — Golden function.** `expected_pwm_high()` in `tb/common/dut_pkg.sv`. Test it from
      a plain `initial` block against a few hand-computed values *before* any UVM touches it.
      *Gate:* prints match `02_design_under_test.md` §1.
- [ ] **A3 — Sequence item.** `pwm_item` with one `rand` field and field macros. *Gate:*
      compiles; a throwaway `initial` block can `create` one, `randomize` it, and `print` it.
- [ ] **A4 — Driver + sequencer + a trivial sequence + base test.** No monitor, no
      scoreboard yet. *Gate:* driver's `uvm_info` prints each item it receives, and the
      waveform shows `duty` changing.
- [ ] **A5 — Monitor.** Publishes observed `(duty, high_cycles, period)` on an analysis port,
      with a subscriber that just prints. *Gate:* printed observations match the waveform.
- [ ] **A6 — Scoreboard.** Compares monitor output to `expected_pwm_high()`. *Gate:* passes
      clean; then **deliberately break the golden function** (change `-1` to `-2`), confirm
      it fails loudly, and put it back. A scoreboard you have never seen fail is a scoreboard
      you cannot trust.
- [ ] **A7 — Coverage.** `pwm_coverage` subscriber with a covergroup on `duty`. *Gate:*
      coverage report shows non-zero, and at least one bin unfilled by the smoke test.
- [ ] **A8 — Assertions.** `tb/common/sva/pwm_n_bit_sva.sv`, attached with `bind`. *Gate:*
      passes on good RTL; temporarily flip `<` to `<=` in a *copy* of `pwm_n_bit.sv` and
      confirm the assertion fires.
- [ ] **A9 — Test suite.** `pwm_smoke_test`, `pwm_random_test`, `pwm_corner_test`,
      `pwm_duty_change_test`, `pwm_reset_test`.

**Phase gate:** `make PHASE=pwm TEST=pwm_random_test SEED=<n>` passes for ten different
seeds, coverage above 90% on the duty covergroup, and you can explain out loud what the
sequencer does that the sequence does not.

---

## Phase B — `magnitude_clamp` (3–4 days)

Combinational DUT. All the difficulty moves into stimulus quality, which is the point.

- [ ] **B1 — Interface without a clocking block, on purpose.** Drive and sample in the same
      timestep. *Gate:* you observe a flaky or off-by-one-item mismatch. Write down what you
      saw — this is `tutorials/T1`'s lesson made concrete.
- [ ] **B2 — Add the clocking block.** Same test now stable across 20 seeds. *Gate:* the
      failure from B1 is gone; you can articulate why.
- [ ] **B3 — Golden function** `expected_clamp()` in `dut_pkg`, returning both magnitude and
      direction.
- [ ] **B4 — Agent, reusing the Phase A template.** *Gate:* random test runs clean.
- [ ] **B5 — Corner constraints.** A `dist`-weighted constraint that hits `0`, `±1`,
      `±CLAMP_VAL`, `±(CLAMP_VAL+1)`, `32'h8000_0000` and `32'h7FFF_FFFF` far more often than
      uniform random would. *Gate:* `pwm`-style coverage report shows every corner bin hit
      within 200 items.
- [ ] **B6 — Parameterize.** Run the same agent and tests at `CLAMP_VAL` = 100, 255, 4095.
      *Gate:* all three pass with no source changes, only a parameter override.
- [ ] **B7 — Assertions + coverage cross** (`sign × magnitude_band × saturated`), with
      `ignore_bins` for the impossible combinations.

**Phase gate:** all three `CLAMP_VAL` configurations pass across ten seeds; the INT_MIN case
is covered and you have written down in `docs/results.md` what the DUT does with it and
whether that is correct.

---

## Phase C — `decoder_to_32_bit` (1.5–2 weeks)

The phase that makes this project worth putting on a resume. Your driver stops writing
values and starts **speaking a protocol**.

- [ ] **C1 — Read the counting rules** in `02_design_under_test.md` §3 until you can draw the
      state diagram from memory. This DUT is not a textbook 4× quadrature decoder and
      assuming it is will cost you two days.
- [ ] **C2 — `quad_if` + `tb_quad_top`,** plus a hand-written `initial` block that walks one
      forward revolution. *Gate:* `count` increments as predicted.
- [ ] **C3 — `quad_item`** with `n_steps`, `direction`, `step_period_clks`, `inject_dither`,
      `dither_count`, and constraints keeping the step period legal.
- [ ] **C4 — Protocol driver.** Translates one item into a pin-level Gray sequence with the
      requested timing. *Gate:* waveform shows a clean `00→10→11→01→00` at the requested rate.
- [ ] **C5 — Reconstruction monitor.** Watches `pulse`/`dir`, publishes observed net
      displacement. Must handle the synchronizer's `x` window at time zero. *Gate:* observed
      displacement matches commanded, for forward and reverse.
- [ ] **C6 — Scoreboard** holding a running expected count against `count`.
- [ ] **C7 — Sequence library:** `quad_forward_seq`, `quad_reverse_seq`, `quad_reversal_seq`,
      `quad_dither_seq`, `quad_fast_seq`, and a composing sequence that picks randomly among
      them.
- [ ] **C8 — Assertions:** `pulse` never high two cycles running; `count` changes only when
      `pulse` is high; the delta is exactly ±1; `dir` stable between pulses.
- [ ] **C9 — Transition coverage** on all sixteen `{a_sync, b_sync}` state transitions, plus
      a cross of direction against step rate.

**Phase gate:** the dither test proves net-zero displacement over 100 rattles at a detent;
the reversal test passes across 20 seeds; transition coverage is at 100% or you have written
down which transitions are unreachable **and why**.

---

## Phase D — `prop_ctrl_pwm` (1.5–2 weeks)

The payoff. If Phases A and C were built properly, you reuse both agents **without
modification** — and if you cannot, that tells you something about how you built them.

- [ ] **D1 — Simulation parameter set.** Instantiate the DUT at `PWM_CLK_FREQ_HZ ≈ 98_000`
      instead of 490 (arithmetic in `02_design_under_test.md` §6). *Gate:* a PWM period is
      about 1024 clocks, not 204,800.
- [ ] **D2 — `ctrl_if` + `ctrl_agent`** driving `reference` and `k`. Small — one item, one
      driver, one monitor.
- [ ] **D3 — Environment** instantiating the quad agent (active), the ctrl agent (active) and
      the pwm agent (passive). *Gate:* all three monitors publishing; no scoreboard yet.
- [ ] **D4 — Control-law golden model** in `dut_pkg`: `expected_error_scaled()` and the
      chain down to `(dir, pwm_cmp)`. Watch the one-clock `ref_position` latency.
- [ ] **D5 — Scoreboard** correlating the three streams. This is the hardest single component
      in the project; `07_phase_d_integration.md` walks through the synchronization strategy.
- [ ] **D6 — Closed-loop convergence test.** A sequence that reads the current position,
      steps the encoder toward the reference, and asserts the PWM command shrinks
      monotonically to zero. *Gate:* converges from at least five random starting errors.
- [ ] **D7 — The `k` overflow investigation.** Sweep `k` up past `2**31 / |error|`, watch the
      truncated product wrap and the direction bit flip. Decide: bug, or out of spec?
      Write the argument down in `docs/results.md`, and add the assertion either way.
- [ ] **D8 — Slow sanity test** at production parameters (`PWM_CLK_FREQ_HZ = 490`), one seed.

**Phase gate:** the full test list passes across ten seeds at sim parameters plus one run at
production parameters; `docs/results.md` has a written verdict on the `k` overflow with your
reasoning.

---

## Phase E — Regression, coverage, packaging (~1 week)

- [ ] **E1 — `regress.py`** running every test across N seeds, producing a pass/fail table,
      exiting non-zero on any failure. Script is in `01_toolchain.md`.
- [ ] **E2 — Coverage merge and report** via `xcrg`. Find the working invocation for your
      Vivado version and record it in the README.
- [ ] **E3 — Coverage closure.** For each hole: add stimulus, or write down why it is
      unreachable. "Unreachable because X" with an argument is a legitimate and expected
      answer; an unexplained hole is not.
- [ ] **E4 — `docs/results.md`.** Every observation from `02_design_under_test.md`,
      classified as **bug** / **limitation** / **out of spec**, with your reasoning and the
      evidence.
- [ ] **E5 — README** with the architecture diagram, how to run, coverage numbers, and honest
      scope limits.
- [ ] **E6 — Interview prep.** Work through the self-quiz in `09_portfolio.md`. Answer out
      loud. The ones you stumble on are the ones you should go re-read.

**Phase gate:** `python3 sim/regress.py` exits 0, the coverage report is committed, and you
can give a five-minute walkthrough of the architecture without notes.

---

## Progress tracker

| Phase | Started | Gate passed | Notes |
|---|---|---|---|
| 0 | | | |
| A | | | |
| B | | | |
| C | | | |
| D | | | |
| E | | | |

---

## If you get stuck

**More than a day on one component** — you have probably skipped an increment. Go back to the
last step whose gate passed and re-add one piece at a time.

**"It compiles but nothing happens"** — objections. `tutorials/T3`.

**"It runs forever"** — also objections, the other direction. `tutorials/T3`.

**"Virtual interface is null"** — `config_db` path mismatch. `tutorials/T4`.

**"The scoreboard is off by one item"** — driver/monitor race. `tutorials/T1`.

**"I don't understand why this class exists"** — a fair question, and worth answering rather
than cargo-culting. `tutorials/T5` and `T6` cover why the factory and TLM earn their keep.
If after reading you still think a component is pointless *for this project*, say so in your
README. Knowing which parts of UVM are overhead for a small design is a more advanced
position than using all of it uncritically.
