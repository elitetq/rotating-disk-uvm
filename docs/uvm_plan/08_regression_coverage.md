# Phase E — Regression, Coverage Closure, and Results

**Goal:** turn a collection of tests into evidence.

**Time:** about a week. **Prerequisite:** Phase D gate passed.

A pile of passing tests is not a verification result. The result is: *this is what I checked,
this is how thoroughly, this is what I found, and this is what I could not reach and why.*
That document is the artifact. The testbench is how you produced it.

---

## Step E1 — Regression

`regress.py` is given complete in `01_toolchain.md`. Wire it up and make it part of your
workflow.

### What a regression is for

Not "run everything once." A regression exists to answer two questions:

1. **Did a change break something that used to work?** Run it before every commit that
   touches shared code (`dut_pkg`, an agent, an interface).
2. **Does the environment find bugs across the random space, not just on seed 1?** A test
   that passes on seed 1 and fails on seed 7 is a test that was passing by accident.

### Seed policy

- Development: fixed seed 1, so runs are reproducible while you iterate.
- Regression: seeds 1–N, all recorded. `--seeds 10` to start, `--seeds 50` before you call
  it done.
- **Every failure must be reproducible from the printed command line.** `regress.py` prints
  it for you. If a failure is not reproducible, the environment has non-determinism in it —
  usually `$random` or `$urandom` called outside the seeded stream, or a race — and that is a
  bug in your testbench that must be fixed before anything else.

### Runtime budget

Rough expectations at simulation parameters:

| Phase | Per test | × 10 seeds | Notes |
|---|---:|---:|---|
| A | seconds | ~1 min | |
| B | seconds | ~1 min | ×3 parameter configs |
| C | seconds–a minute | ~5 min | `quad_fast_test` is the slow one |
| D | ~1 min | ~10 min | `ctrl_slow_test` is minutes on its own |

A full regression in well under half an hour. If yours is materially worse, look at
sequence lengths before looking at the simulator — `n_steps` of 5000 checks nothing that
`n_steps` of 200 did not.

### Gate E1

`python3 sim/regress.py --seeds 10` runs clean from a fresh clone and exits 0. Commit the
output as `docs/regression_log.txt`.

---

## Step E2 — Collecting coverage

```bash
make PHASE=pwm  TEST=pwm_random_test  SEED=1 COV=1 run
make PHASE=pwm  TEST=pwm_corner_test  SEED=1 COV=1 run
# ... and so on across the suite
make cov        # merge → sim/cov_report/index.html
```

**The flags move between Vivado releases.** Before relying on the Makefile's version:

```bash
xsim -help | grep -i cov
xcrg -help
```

Fix the Makefile once against what your 2025.2 accepts, and **write the working invocation
into your README**. That one line will save the next person — probably you, in six months —
half an hour.

### If the XSim coverage flow fights you

It sometimes does. The fallback is entirely legitimate: have each coverage subscriber print
its numbers in `report_phase`.

```systemverilog
  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("cg_pwm_duty  = %.2f%%", cg_pwm_duty.get_coverage()),  UVM_LOW)
    `uvm_info("COV", $sformatf("cg_saturated = %.2f%%", cg_saturated.get_coverage()), UVM_LOW)
  endfunction
```

Then have `regress.py` grep those lines and build the table. You lose the merged HTML report
and per-bin detail; you keep the numbers that matter. **Say so in the README** — "functional
coverage collected via in-testbench reporting; XSim's merge flow was not used" is a normal
engineering trade-off, stated plainly. Pretending you had tooling you did not is the only
wrong move.

---

## Step E3 — Coverage closure

The part people skip, and the part that separates a demo from a verification project.

### The process

For every bin below its goal, exactly one of three outcomes. No fourth option.

**1. Add stimulus.** The bin is reachable and you just did not aim at it. Write the
constraint or the directed sequence. Most holes are this.

**2. Argue unreachable.** The bin describes a state the design cannot enter. Write the
argument next to the `ignore_bins`:

```systemverilog
  // ignore_bins: {a_sync,b_sync} 00 => 11 requires both encoder channels to
  // change within one clk. A quadrature encoder is mechanically incapable of
  // this — the channels are 90 degrees out of phase by construction — and the
  // driver enforces one-channel-at-a-time (see the a_no_double_channel_change
  // assertion). Excluded as physically unreachable, not as untested.
  ignore_bins impossible_diagonal = (2'b00 => 2'b11), (2'b11 => 2'b00),
                                    (2'b10 => 2'b01), (2'b01 => 2'b10);
```

That comment is the deliverable. `ignore_bins diagonal = ...;` with no comment is
indistinguishable from hiding a hole.

**3. Accept with a documented reason.** Rare, but real: "the bin requires `k > 2²²`, which is
outside the declared legal range R-CTL-4; characterized separately in
`ctrl_gain_sweep_test`."

### What good looks like

```
cg_pwm_duty          100.00%   (8/8 bins)
cg_clamp_cross        100.00%   (15/15 bins, 6 ignored — see comments)
cg_quad_state          100.00%   (16/16 transitions, 4 ignored — physically unreachable)
cg_quad_rate           100.00%   (10/10 bins)
cg_ctrl_error           93.75%   (15/16 bins — see note)
cg_ctrl_k              100.00%   (6/6 bins)
cg_ctrl_converged      100.00%   (1/1)
```

with a note for the 93.75%:

> `cg_ctrl_error` cross bin `{sign=negative, band=exact_clamp, k=near_overflow}` unfilled.
> Reachable in principle but requires the solver to hit `|error| × k` within a narrow band
> around 2³¹ while `|error_scaled|` lands exactly on `2**BITS − 1`. Estimated at fewer than
> 1 in 10⁵ random items. Left open rather than adding a directed test, because
> `ctrl_gain_sweep_test` already characterizes the overflow boundary directly and the
> saturation path is covered by six other bins.

**That is what closure looks like:** a number, and for anything short of 100%, a reason
someone else can evaluate.

### The trap

Do not chase 100% by deleting bins. If you find yourself adding `ignore_bins` because a bin
is hard rather than because it is unreachable, you have inverted the purpose of the exercise.
Coverage is a measurement instrument; adjusting the instrument to read what you want is not
a result.

---

## Step E4 — `docs/results.md`

The most valuable file in the repo. Structure:

```markdown
# Verification Results

## Summary
One paragraph: what was verified, at what level, with what outcome.

## Environment
Simulator and version, UVM version, host OS, how to reproduce.

## Test results
The regression table. Tests × seeds × pass/fail.

## Coverage
The numbers, per covergroup, with the closure notes.

## Findings
The observation register from 02_design_under_test.md §7, filled in.
One subsection per finding that got a non-trivial verdict.

## Modelling assumptions and their discharge
M1 BUFG stub, M2 parameter override, M3 ideal encoder edges, M4 clean clock.
For each: what it was, why it was acceptable, and how it was discharged.

## Not verified
Explicit list, with reasons. Being clear about this is a feature.
```

### Writing a finding

Each substantive finding gets the same five parts:

1. **What** the behaviour is, precisely.
2. **Why** it happens — the mechanism in the RTL.
3. **When** it matters — is the deployed configuration affected?
4. **Verdict** — bug / limitation / out of spec, and the argument.
5. **Recommendation**, with a cost estimate if you are proposing a fix.

The `k` overflow write-up in `07_phase_d_integration.md` §D7 is the worked example. Match
that shape for O-PWM-1, O-PWM-3, O-QUAD-1, O-LED-1 and O-DIV-1.

O-PWM-1 is the one with a fix attached, so it gets a sixth part: **what the fix changed, and
what it left behind.** Upstream could not reach 100% duty; `rtl/pwm_n_bit.sv` now can
(`rtl/PROVENANCE.md` §2); the residual is the `duty → duty + 1` offset recorded as R-PWM-7.
Write all three. A finding, a fix, and an honest account of the fix's own limitation is a
stronger entry than a finding alone.

### And the one that started it all

Include the Step 0 `position` bug, even though you fixed it before writing a single line of
UVM. It belongs in the record:

> **F-000 — open control loop (fixed before verification began).** The `mvp_changes`
> refactor hoisted `decoder_to_32_bit` out of `controller` into `prop_ctrl_pwm` but left
> `controller.position` both redeclared internally and unconnected at the instance, reported
> by Vivado as Synth 8-11121 / 8-7071 / 8-7023. The proportional loop was open: `error`
> reduced to `−ref_position` regardless of actual disk position. Fixed by removing the stale
> declaration and connecting the port. Requirement **R-SYS-6** and the CHECK-1 direction
> comparison in the Phase D scoreboard now guard against a recurrence.

Two things make that entry good. It is honest about the timeline — you did not pretend UVM
found it. And it closes the loop by naming the specific requirement and check that now
prevent it. A bug found is worth something; a bug found *and permanently fenced off* is worth
more.

---

## Step E5 — Optional: mutation testing

If you have time and want one more genuinely strong result, this is the highest-value thing
you can add.

**The question it answers:** *how do I know my testbench would catch a bug?* Passing tests
prove the design is right, or prove the tests are weak — and you cannot tell which from the
result alone.

**The method:** deliberately break the RTL in small, realistic ways, and confirm the
environment fails on each one.

```
rtl/mutants/
  m01_pwm_lt.sv             Q < duty instead of Q <= duty  (= upstream; reverts R-PWM-4)
  m02_pwm_threshold.sv      duty >= THRESHOLD instead of duty > THRESHOLD
  m03_clamp_sign.sv         dir inverted
  m04_clamp_no_sat.sv       saturation removed
  m05_quad_lock.sv          up_lock check removed
  m06_quad_dir.sv           dir inverted on the down path
  m07_ctrl_sign.sv          error = ref_position − position (sign flipped)
  m08_ctrl_no_ref_reg.sv    ref_position combinational instead of registered
```

Add a `--mutants` mode to `regress.py` that, for each mutant, swaps it into the filelist,
runs the relevant tests, and asserts the environment **fails**. Produce a table:

| Mutant | Description | Detected by | Result |
|---|---|---|---|
| m01 | `Q < duty` (upstream) | `pwm_random_test` scoreboard, `a_out_relation` | **killed** |
| m05 | lock check removed | `quad_dither_test` | **killed** |
| m08 | `ref_position` unregistered | `ctrl_random_test` CHECK 1 | **killed** |
| … | | | |

A mutant that **survives** is the interesting one — it means a real class of bug would slip
through. That is a hole in your test plan, and finding one before someone else does is the
entire job.

Report it as *mutation score: N/M killed*. Very few portfolio projects have that number, and
anyone who has done real DV will recognize immediately what it means.

---

## Phase E gate

- [ ] `python3 sim/regress.py --seeds 10` exits 0 from a clean clone.
- [ ] Coverage collected, merged or reported, and committed under `docs/coverage/`.
- [ ] Every bin at goal, or holed with a written argument.
- [ ] `docs/results.md` complete: every observation has a verdict, every assumption is
      discharged, the out-of-scope list is explicit.
- [ ] Every assertion has been observed firing at least once against broken RTL.
- [ ] README written (template in `09_portfolio.md`).
- [ ] Optional: mutation score recorded.

### Explain these out loud

1. Why does a test that passes on seed 1 but fails on seed 7 mean the seed-1 pass was
   worthless?
2. What is the difference between an unreachable bin and a bin you did not reach?
3. Your regression is green and coverage is 100%. What could still be wrong?
4. What does mutation testing measure that coverage does not?
