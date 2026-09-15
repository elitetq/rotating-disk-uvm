# Packaging It

You built the thing. Now make it legible to someone who has thirty seconds, and defensible
to someone who has thirty minutes.

---

## 1. README template

The README is read by two people: a recruiter skimming, and an engineer who will open the
source. Serve both — summary at the top, detail below.

````markdown
# Rotating Disk Controller — UVM Verification Environment

A SystemVerilog/UVM environment verifying a proportional position controller for a
quadrature-encoded rotating disk, built from scratch on Vivado XSim.

**Design under verification:** FPGA position controller — quadrature decoder, proportional
control law, magnitude clamp, N-bit PWM generator, H-bridge direction logic. Originally
built for ENEL 441/453 and running on hardware.

**Environment:** 4 UVM agents (3 reusable), constrained-random stimulus, pure-function
golden models, SVA bound to the RTL, functional coverage, seeded regression.

---

## Results at a glance

| | |
|---|---|
| Blocks verified | 4 (`pwm_n_bit`, `magnitude_clamp`, `decoder_to_32_bit`, `prop_ctrl_pwm`) |
| UVM tests | 21 |
| Regression | 21 tests × 10 seeds, all passing |
| Functional coverage | 100% on 6 of 7 covergroups (7th documented at 93.75%) |
| Assertions | 17, each validated against seeded faults |
| Findings | 6 recorded — 1 defect, 4 limitations, 1 out-of-spec |
| Mutation score | 8/8 mutants killed |

Full write-up: [`docs/results.md`](docs/results.md).
Verification plan: [`docs/verification_plan.md`](docs/verification_plan.md).

---

## Architecture

```
                 tb_ctrl_top (module)
   clk/reset gen · virtual interfaces → config_db · bind: SVA → RTL
                          │
        ┌─────────────────┴──────── ctrl_env ────────────────────┐
        │                                                        │
  ┌─────┴──────┐   ┌────────────┐   ┌───────────┐   ┌──────────┐ │
  │ quad_agent │   │ ctrl_agent │   │ pwm_agent │   │predictor │ │
  │  ACTIVE    │   │  ACTIVE    │   │  PASSIVE  │   │ (model)  │ │
  │ protocol   │   │ ref, gain  │   │ duty meas.│   │          │ │
  │ driver     │   │            │   │  (reused) │   │          │ │
  └─────┬──────┘   └─────┬──────┘   └─────┬─────┘   └────┬─────┘ │
        └────────────────┴────────────────┴──────────────┤       │
                                                          ▼       │
                                          ┌───────────────────┐   │
                                          │   scoreboard      │   │
                                          │ + coverage        │   │
                                          └───────────────────┘   │
        └─────────────────────────────────────────────────────────┘
```

`quad_agent` and `pwm_agent` were built at block level (Phases A and C) and reused unchanged
at subsystem level — `pwm_agent` in passive mode, observing the PWM output inside the DUT.

---

## Running it

```bash
export XILINX_ROOT=$HOME/Vivado/2025.2
export PATH=$XILINX_ROOT/Vivado/bin:$PATH

cd sim
make PHASE=ctrl TEST=ctrl_convergence_test SEED=1 run   # one test
python3 regress.py --seeds 10                            # full regression
make PHASE=ctrl TEST=ctrl_convergence_test WAVES=1 run   # with waveform
```

Requires Vivado 2025.2 (XSim + its bundled UVM 1.2). No other dependencies.

---

## Notable findings

**Proportional gain overflow.** `controller` truncates `error × k` to 32 bits. Above
`|error| × k ≥ 2³¹` the product wraps and the sign bit inverts, so the H-bridge drives the
motor *away* from the target at saturated effort. Boundary measured at `k = 4 194 304` for
one revolution of error, matching prediction. The deployed configuration hardcodes `K = 1`
and is unaffected; recommended a saturating multiply (one comparator and a mux).

**Encoder rate limit.** The decoder's lock-clear requires the `00` detent to persist for two
synchronized samples, so counts are dropped above ~12.5 M quadrature cycles/s. Predicted from
the synchronizer depth, then measured — margin over the physical maximum is ~1500×.

**LED bar aliasing at `BITS > 8`.** `led_status` receives only `pwm_cmp[7:0]`, so at the
module's default `BITS = 12` the display goes dark at high effort. Not reachable in the
deployed `BITS = 8` configuration; found by running the environment across the parameter
space rather than at a single operating point.

Full analysis in [`docs/results.md`](docs/results.md).

---

## Scope

**Verified:** `pwm_n_bit`, `magnitude_clamp`, `decoder_to_32_bit` (with
`first_value_priority`, `synchronizer`, `directional_counter`), `prop_ctrl_pwm`.

**Not verified:** `enel453_lab_initializer`, `debounce`, `status_7seg`, `top_module`.
Behavioural simulation only — no gate-level or timing verification.

**Modelling assumptions:** `BUFG` replaced by a wire for simulation;
`PWM_CLK_FREQ_HZ` overridden from 490 to 98 000 for regression speed, with one test at
production parameters. Both documented and discharged in `docs/results.md`.

**Regression runs locally only.** XSim cannot run in GitHub Actions, so there is no CI.
````

### Two things to keep in that README

**The scope section.** It is the most credible part. Anyone experienced reads "not verified"
first, and its absence is a bigger signal than anything in the results table.

**The assumptions.** `BUFG` is a wire and the clock divider ratio is wrong on purpose. Both
are correct engineering decisions. Both are also things a reviewer will spot in the source,
so say them first.

---

## 2. Resume phrasing

The trap is claiming more than you did. Everything below is defensible from the repo.

**Bullet, project-list style:**

> **UVM verification environment, FPGA motion controller** — Built a SystemVerilog/UVM
> testbench from scratch (4 agents, constrained-random stimulus, SVA, functional coverage,
> seeded regression) for a quadrature-encoder position controller. Closed coverage across 7
> covergroups and reported 6 design findings including an arithmetic-overflow runaway
> condition in the proportional gain path.

**Bullet, skills-emphasis style:**

> **SystemVerilog / UVM** — Block- and subsystem-level environments with reusable agents,
> protocol drivers, reconstruction monitors, pure-function reference models, SVA bound to
> RTL, and functional-coverage closure. Verified an FPGA proportional position controller
> across four blocks; 21 tests, 8/8 seeded mutants detected.

**One-liner for a skills section:**

> SystemVerilog, UVM, SVA, functional coverage, constrained-random verification, Vivado XSim

### Say and do not say

| Say | Do not say |
|---|---|
| "Built a UVM environment for a design I wrote" | "Industry-standard verification methodology" (says nothing) |
| "Reported an overflow condition in the gain path" | "Found critical bugs" (unless they were) |
| "Closed functional coverage across 7 covergroups" | "100% coverage" (you have a documented 93.75%) |
| "Block- and subsystem-level" | "Full-chip" (you scoped `top_module` out) |
| "8/8 seeded mutants detected" | "Exhaustively verified" |

The overclaim costs you more than the underclaim ever will. An interviewer who catches one
inflated bullet discounts the rest of the page.

### About the `position` bug

Do **not** put "found a bug in my own design" on the resume — you fixed it before the UVM
work began and the timeline will not survive a follow-up question. It is a great *story* for
the interview, told accurately:

> "Vivado's synthesis log had been flagging an unconnected port for a while and I'd been
> ignoring the warning. When I started scoping the verification work I actually read it — a
> refactor had left the position feedback disconnected, so the control loop was open. I fixed
> it before building anything, then wrote an explicit requirement and a cycle-by-cycle
> direction check so it can't come back. It's the reason I take synthesis warnings seriously
> now."

That answers "tell me about a bug you found" and "tell me about a time you were wrong" at
once, and the self-aware version is worth more than a heroic one.

---

## 3. Interview self-quiz

Answer these **out loud**, from memory. Stumbling is information — go re-read.

### UVM structure

**1. What does a sequencer do that a sequence does not?**
A sequence generates transactions. The sequencer arbitrates: it owns the connection to the
driver, decides which sequence's item goes next when several are running, and manages the
handshake. Sequences are stimulus; the sequencer is traffic control.

**2. Walk the path of one transaction from sequence to pins.**
`start_item(req)` blocks until the sequencer grants → randomize → `finish_item(req)` hands it
over → sequencer passes it to the driver's `seq_item_port` → driver's `get_next_item()`
returns → driver converts it to pin wiggles through the clocking block →
`item_done()` releases the sequencer for the next item.

**3. Why does a driver exist separately from a sequence?**
Separation of *what* from *how*. The sequence says "turn forward 50 steps"; the driver knows
that means a Gray-coded pin sequence with specific timing. Change the pin protocol and only
the driver changes; every sequence still works.

**4. What is the factory for?**
Replacing a component or object type without editing the code that instantiates it.
`type_id::create()` asks the factory rather than calling `new()`, so a test can call
`set_type_override_by_type()` to substitute an error-injecting driver into an environment it
does not own.

**5. Did you actually use a factory override?**
Answer honestly. "No — the environment is small enough that I configured behaviour through
`config_db` instead, but I used `type_id::create` throughout so an override is available"
is a better answer than a fabricated one. Knowing when you did not need a feature is a
stronger position than using everything.

**6. What is `uvm_config_db` for and how do components find their values?**
A hierarchical key-value store. `set()` writes with a scope path (wildcards allowed);
`get()` reads by matching the caller's full instance path. It is how a virtual interface gets
from the module-level testbench into a class that cannot reference hierarchy directly.

**7. Why can't a class just reference the interface directly?**
Classes are dynamic objects with no place in the static module hierarchy. A *virtual*
interface is a handle to a static instance, and the handle has to be passed in from
somewhere that can see the hierarchy — the testbench top.

**8. What are UVM phases and why do they exist?**
An ordered set of synchronization points across every component: `build` (top-down,
construct), `connect` (bottom-up, wire TLM), `end_of_elaboration`, `run` (parallel, the only
time-consuming one), then the report phases. They exist so components can be built and
connected in a defined order without knowing about each other.

**9. Why is `build_phase` top-down and `connect_phase` bottom-up?**
A parent must exist before it can create children, so building goes down. Connecting needs
children's ports to exist already, so it goes up.

**10. What is an objection?**
A vote that the simulation should keep running. The run phase ends when the objection count
reaches zero. Raise at the start of your test's `run_phase`, drop when the stimulus is done —
forget the raise and the sim ends at time 0 with a false pass; forget the drop and it hangs.

**11. What is TLM and why not just call a function?**
Analysis ports decouple producer from consumer. The monitor calls `ap.write(obs)` without
knowing whether zero, one or five subscribers exist. Add a coverage collector later and the
monitor does not change. A direct call would require the monitor to hold a handle to every
consumer.

**12. `uvm_analysis_port` vs `uvm_analysis_imp` vs `uvm_analysis_export`?**
`port` produces, `imp` implements `write()` and consumes, `export` forwards a child's
interface up through a hierarchy without implementing it.

**13. What is `uvm_analysis_imp_decl` for?**
One class can only implement `write()` once. The macro generates suffixed variants
(`write_quad`, `write_ctrl`) so a single scoreboard can receive several differently-typed
streams.

### SystemVerilog

**14. What is a clocking block and what does it prevent?**
It defines sampling and driving skews relative to a clock edge. Inputs sample in the preponed
region — the same instant the DUT's flops do — and outputs drive after the edge. Without it,
the driver, monitor and DUT are all sensitive to the same edge in an order the language does
not define, so what the monitor sees depends on scheduler order rather than on logic.

**15. You saw that race. Describe it.**
From Phase B, step B1. In your own words, including what the symptom looked like.

**16. `#1step` — what does it mean?**
Sample in the preponed region of the timestep, before any nonblocking updates. Not "one time
unit" — a distinct simulation region.

**17. Blocking vs nonblocking assignment, and which does a driver use?**
`=` executes immediately in order; `<=` schedules an update at the end of the timestep. Use
`<=` for sequential logic and for clocking-block drives, so the driver behaves like a flop
rather than racing combinationally.

**18. `logic` vs `wire` vs `reg`?**
`logic` is a 4-state type that can be driven procedurally *or* by a single continuous
assignment. `wire` allows multiple drivers with resolution. `reg` is the Verilog-2001
ancestor of `logic`. Use `logic` unless you need multiple drivers.

**19. `:=` vs `:/` in a `dist` constraint?**
`:=` gives *each* value in the range that weight; `:/` divides the weight *across* the range.
`[1:100] := 10` totals 1000; `[1:100] :/ 10` totals 10.

**20. What does `randomize()` return and what should you do with it?**
0 if the constraints are unsatisfiable. Always check it. `void'(x.randomize())` in production
code silently produces stale values when a constraint conflicts.

**21. `|->` vs `|=>`?**
Overlapping vs non-overlapping implication. `|->` evaluates the consequent in the same cycle
the antecedent matches; `|=>` on the next cycle. `|=>` is `|-> ##1`.

**22. What does `disable iff` do, and why does every assertion here need it?**
Aborts evaluation while the condition holds. Without `disable iff (reset)`, every in-flight
property fails when reset asserts mid-sequence — noise, not findings.

**23. What is `bind` and why use it?**
Attaches a module (typically assertions) into another module's scope without editing its
source. The RTL stays exactly as it synthesizes, the checker sees internal signals, and one
bind statement covers every instance of that module type at every level.

### This design specifically

**24. Your DUT multiplies a signed value by an unsigned one. Is that a bug?**
No — because the result is truncated to 32 bits, and signed and unsigned multiplication
produce identical low-order bits. Both are `(a × b) mod 2³²`. It *would* be a bug if the
upper bits were used. The real hazard is overflow past 2³¹, which is a separate issue.

**25. How did you verify that claim rather than argue it?**
Modelled the truncation exactly in `dut_pkg`, then ran thousands of random `(error, k)` pairs
through the scoreboard, with a covergroup proving both signs and the saturation boundary
were exercised.

**26. Your decoder counts once per quadrature cycle, not four times. How did you find that
out, and did it change your testbench?**
From reading the pulse conditions — every one of them requires the other channel low, so only
transitions touching the `00` state count, and the lock suppresses the second one. It changed
the golden model entirely: an assumed 4× decoder would have predicted four counts per
revolution and failed every test.

**27. What is the encoder rate limit and how did you find it?**
The lock clears only when `00` is observed for two consecutive synchronized samples, so the
`00` quarter-cycle must last at least two clocks — about 12.5 M quadrature cycles/s at
100 MHz. Predicted from the RTL, then measured with a sequence sweeping the step period down
to the knee. They matched.

**28. Why is the PWM agent passive at subsystem level?**
Nothing external drives `duty` there — the DUT's own clamp does. The agent exists to reuse
the monitor's duty measurement on `motor_en`. Building the active/passive split at block
level is what made that free.

**29. You changed a parameter to speed up simulation. Justify it.**
`PWM_CLK_FREQ_HZ` only sets the clock-divider ratio, which the PWM logic never observes;
200× faster with identical behaviour. It would *not* be legitimate to change `BITS`, which
sets the duty resolution and the clamp value — the things actually under test. One test runs
at production parameters to discharge the assumption.

**30. Your regression is green and coverage is closed. What could still be wrong?**
Plenty. Coverage measures what the stimulus reached, not what the checks caught — a hole in
the *checkers* is invisible to it. The golden model could share a misconception with the RTL,
since both came from me. Behaviour outside the declared parameter ranges is uncharacterized.
And it is behavioural simulation: nothing here says anything about timing closure or
metastability in silicon. Mutation testing addresses the first of those; the rest are stated
as limitations.

**31. If you had another month, what would you do?**
Have a real answer. Candidates: a `top_module` environment with button/switch agents; formal
property checking on the decoder's lock FSM, where it would be genuinely stronger than
simulation; a reference model in C via DPI to remove the shared-misconception risk in
question 30; gate-level simulation with SDF.

---

## 4. A five-minute walkthrough

Practise this until it flows without notes.

1. **(30 s) What the design does.** Proportional position controller for a disk with a
   quadrature encoder. Reference in, encoder in, PWM and direction out to an H-bridge.
2. **(45 s) Why verify it.** It worked on hardware, which proves it works for the cases I
   tried. I wanted to know what it does across the input space, and to learn UVM on a design
   I understood completely.
3. **(60 s) Architecture.** Four agents, three reusable. Golden models as pure functions in a
   package, so the scoreboards are ten lines each and the same model backs the assertions.
   Assertions bound in, so the RTL is untouched.
4. **(90 s) The interesting part.** Pick one — the quadrature protocol driver, or the
   overflow finding. Tell it as: what I predicted from the RTL, how I designed the
   experiment, what I measured, what I concluded.
5. **(45 s) Results.** Coverage, tests, findings, and the one bin you left open and why.
6. **(30 s) Limits.** What is out of scope, and the two modelling assumptions.

Step 4 is the one that matters. Steps 1–3 show you can build a testbench; step 4 shows you
can *verify*, which is a different and rarer thing.
