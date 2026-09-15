# Building a UVM Verification Environment for the Rotating Disk Controller

A self-teaching guide. You write every line of the testbench; this guide tells you what to
write, why, in what order, and how to know when each piece works.

---

## What this is

You have a working proportional position controller in
`enel441_453_lab.srcs/sources_1/new/`. It is verified today by fifteen directed testbenches
in `sim_1/new/` — the `$display("PASS Check 3: ...")` style. Those are good testbenches.
They prove the design works **for the cases you thought of**.

This guide walks you through replacing that with a UVM environment: constrained-random
stimulus, self-checking scoreboards driven by golden models, SystemVerilog assertions bound
to the RTL, functional coverage, and a seeded regression. The end state is a standalone git
repo you can link from a resume, plus the ability to answer the questions an interviewer
will ask about it.

**The design is the point.** Every formula, every corner case, every assertion in this guide
was derived from *your* RTL, not from a generic tutorial. `02_design_under_test.md` is the
analysis; the phase guides turn it into a testbench.

## What this is not

- **Not a code drop.** Skeletons here show structure, port lists and boilerplate macros.
  The logic is marked `// TODO(you):` with a hint and usually the name of the method you
  need. If you copy a skeleton and run it, it will compile and do nothing useful. That is
  deliberate.
- **Not a UVM reference manual.** The ten tutorials in `tutorials/` cover the concepts you
  will hit, each in about two pages, and then point you at the canonical sources.
- **Not exhaustive verification.** `enel453_lab_initializer`, `debounce`, `status_7seg` and
  the ROM playback path are out of scope. Say so in your results document — scoping honestly
  is part of the skill.

## The one exception to "you write it"

Build infrastructure — the Makefile, the filelists, `regress.py` — is given complete in
`01_toolchain.md`. Typing a Makefile teaches you nothing about verification, and a broken
build will stall you for a day. Copy those out and move on.

---

## The ladder

Four DUTs, in increasing difficulty. Each phase reuses what the last one built.

| Phase | DUT | Time | The new idea |
|:--:|---|:--:|---|
| **0** | — | ½ day | Fix a real bug in your RTL, prove UVM runs on XSim, set up the repo. |
| **A** | `pwm_n_bit` | ~1 wk | Every UVM moving part, on a DUT simple enough that any failure is obviously *your* bug. |
| **B** | `magnitude_clamp` | 3–4 d | Constrained randomization. Combinational DUT, so all the difficulty is in the stimulus. |
| **C** | `decoder_to_32_bit` | 1.5–2 wk | A driver that speaks a **protocol** instead of writing values. This is the phase that makes the project worth showing. |
| **D** | `prop_ctrl_pwm` | 1.5–2 wk | Integration: reuse the Phase A and C agents unchanged, model the whole control law, check a closed loop. |
| **E** | — | ~1 wk | Regression, coverage closure, and packaging it so someone else can understand it. |

Roughly six to eight weeks part-time. It is not a weekend project, and the parts that take
longest (C and D) are the parts worth talking about.

---

## How to read this

**Start here, in order:**

1. `01_toolchain.md` — get XSim running UVM *before* you write anything real. Half a day.
2. `02_design_under_test.md` — the analysis of your RTL. Read it once now, then keep it open
   for the rest of the project. Every golden-model formula in the testbench comes from here.
3. `03_verification_plan.md` — fill this in before writing tests. Writing a vplan first feels
   like bureaucracy; it is the difference between "I wrote some random tests" and "I verified
   this design", and interviewers can tell which one you did.
4. `00_roadmap.md` — the checklist you actually work from, with acceptance gates.

**Then, one per phase:** `04_phase_a_pwm.md` → `05_phase_b_clamp.md` →
`06_phase_c_quadrature.md` → `07_phase_d_integration.md` → `08_regression_coverage.md`.

**Reference as needed:** `tutorials/T1`–`T10`, and `09_portfolio.md` at the very end.

### If you have never written a class in SystemVerilog

Read `tutorials/T2_classes.md` before Phase A. It is deliberately short — you need maybe
15% of SystemVerilog's OOP to write UVM, and the guide sticks to that 15%.

### If you have never written an assertion

Read `tutorials/T8_sva_and_bind.md` before Phase A. `bind` in particular is worth learning
early: it lets you attach assertions to a module **without editing the module**, which means
your RTL stays exactly as it synthesizes.

---

## Ground rules that make this work

**Simulate after every increment.** The single most common way to fail at this is to write
six components, hit compile, and face 200 errors with no idea which layer is wrong. Every
phase in this guide is broken into steps that each end with a working simulation. Follow
that.

**When something fails, suspect the testbench first.** Your RTL has been on real hardware.
For the first three phases, if the scoreboard disagrees with the DUT, the scoreboard is
probably wrong. This flips at Phase D.

**Commit at every acceptance gate.** `git log` is the story of the project. A history that
reads "Phase A: driver + sequencer running" → "Phase A: scoreboard catches injected fault"
is worth more than one commit called "uvm stuff".

**Keep a bug/observation log from day one.** `docs/results.md`. Every time you find
something surprising — an off-by-one, an unreachable state, a parameter that breaks
elaboration — write it down with the evidence. That file is the most valuable artifact you
will produce.

---

## Index

| File | What it is |
|---|---|
| `00_roadmap.md` | The working checklist, with per-task acceptance gates. |
| `01_toolchain.md` | XSim + UVM setup, smoke test, Makefile, filelists, regression runner, waveforms, troubleshooting. |
| `02_design_under_test.md` | Analysis of your RTL. Golden-model formulas with derivations, corner cases, parameter traps, runtime math. |
| `03_verification_plan.md` | Verification plan template, partly pre-filled. |
| `04_phase_a_pwm.md` | Phase A build guide — `pwm_n_bit`. |
| `05_phase_b_clamp.md` | Phase B build guide — `magnitude_clamp`. |
| `06_phase_c_quadrature.md` | Phase C build guide — `decoder_to_32_bit`. |
| `07_phase_d_integration.md` | Phase D build guide — `prop_ctrl_pwm`. |
| `08_regression_coverage.md` | Regression, coverage closure, results write-up. |
| `09_portfolio.md` | README template, resume phrasing, interview self-quiz. |
| `tutorials/T1_interfaces.md` | Interfaces, modports, clocking blocks, and the race they prevent. |
| `tutorials/T2_classes.md` | The 15% of SystemVerilog OOP that UVM needs. |
| `tutorials/T3_phases_objections.md` | UVM phases and objections. Why your sim hangs or ends instantly. |
| `tutorials/T4_config_db.md` | `uvm_config_db`, virtual interfaces, and wildcard pitfalls. |
| `tutorials/T5_factory.md` | The factory, `type_id::create`, and overrides. |
| `tutorials/T6_tlm.md` | Analysis ports, subscribers, `uvm_analysis_imp_decl`. |
| `tutorials/T7_randomization.md` | `rand`, constraints, `dist`, `solve...before`, inline constraints. |
| `tutorials/T8_sva_and_bind.md` | SVA and `bind`. |
| `tutorials/T9_coverage.md` | Covergroups, bins, crosses, closure. |
| `tutorials/T10_debugging_xsim.md` | Debugging UVM under XSim specifically. |

---

## Before you start

Two facts you should know going in.

**UVM is object-oriented and there is no way around that.** You chose the lean version, and
this guide holds to it: the class code stays short, formulaic and macro-heavy — roughly 600
lines across the whole project, most of it copy-adapted after Phase A. The interesting work
lives in interfaces, assertions, covergroups, and a package of pure functions that model the
DUT. But you will write classes, and `tutorials/T2` exists so that is not a wall.

**There is a bug in your RTL right now.** It is on the `mvp_changes` branch, your synthesis
log already reported it, and Step 0 has you fix it before anything else. Details in
`00_roadmap.md` and `02_design_under_test.md`. Start there.
