# Rotating Disk Controller — UVM Verification Environment

A UVM testbench for a proportional position controller for a rotating disk: a quadrature
encoder decoder, a magnitude clamp, an N-bit PWM generator, and the closed-loop controller
that ties them together. Constrained-random stimulus, self-checking scoreboards against
golden models, SystemVerilog assertions bound to the RTL, and functional coverage, all
running on Vivado XSim.

> ### ⚠️ Status: not built yet
>
> This is work in progress and early. Today the repo has the build infrastructure, the
> interfaces, the testbench tops and a UVM smoke test; the agents, environments,
> scoreboards, assertions and tests are still stubs. Nothing here verifies anything yet.
> **The commands below describe how it is meant to be driven once it is built** — most of
> them will not do anything useful in the meantime. See
> [Current state](#current-state) for what actually runs.

---

## About this project

This is a **learning project**. I am teaching myself UVM, and I am not a professional
verification engineer — expect things that a practitioner would do differently, and expect
the structure to change as I learn why it should.

**Every line of code in this repo is written by me.** I used Claude for the surrounding
work: planning the build order, explaining concepts, reviewing my reasoning, and writing
the private study notes I work from. The testbench itself — interfaces, agents, golden
models, assertions, covergroups, tests — is mine, typed out by hand, because writing it is
the entire point of the exercise.

The `rtl/` directory is a vendored copy of my own coursework design (see
[`rtl/PROVENANCE.md`](rtl/PROVENANCE.md) for the exact source commit and the two local
changes made to it). It is the device under test, not part of the verification work.

---

## Requirements

| | |
|---|---|
| Simulator | Vivado XSim, 2025.2 (any recent release should work) |
| UVM | UVM-1.2, the copy that ships with Vivado — nothing to install |
| Build | GNU make, Python 3 for the regression runner |

The Makefile looks for Vivado under `$HOME/Vivado/2025.2`. Point it elsewhere with
`XILINX_ROOT`, either per-invocation or in your environment:

```sh
make XILINX_ROOT=/tools/Xilinx/Vivado/2024.1
```

Vivado does not have to be on your `PATH`; the Makefile calls `xvlog`, `xelab`, `xsim` and
`xcrg` by absolute path.

---

## Running a simulation

Everything is driven from the `sim/` directory.

```sh
cd sim
make                    # compile + elaborate + run the default test
```

`make` is compile → elaborate → run in one step; `make compile` and `make elab` stop early
if you only want to check that things build.

### Choosing what to run

The testbench is split into four independent phases, one per device under test. Select one
with `PHASE`, and a test within it with `TEST`:

```sh
make PHASE=pwm                          # the default
make PHASE=clamp TEST=clamp_random_test
make PHASE=quad  TEST=quad_direction_test SEED=42
make PHASE=ctrl  TEST=ctrl_step_response_test VERBOSITY=UVM_HIGH
```

| Knob | Values | Default | What it does |
|---|---|---|---|
| `PHASE` | `pwm`, `clamp`, `quad`, `ctrl` | `pwm` | Picks the DUT, its filelist and its testbench top |
| `TEST` | a UVM test class name | `<PHASE>_smoke_test` | Passed through as `+UVM_TESTNAME` |
| `SEED` | integer | `1` | Randomization seed (`-sv_seed`) |
| `VERBOSITY` | `UVM_LOW`, `UVM_MEDIUM`, `UVM_HIGH`, `UVM_DEBUG` | `UVM_MEDIUM` | UVM report verbosity |
| `WAVES` | `0`, `1` | `0` | Dump a waveform database |
| `COV` | `0`, `1` | `0` | Collect functional coverage |
| `TIMEOUT` | a delay | `20ms` | Global watchdog, read as `+UVM_TIMEOUT` |
| `XILINX_ROOT` | path | `$HOME/Vivado/2025.2` | Where Vivado lives |

`make help` prints the same list.

Which DUT each phase drives:

| Phase | DUT | What it is |
|---|---|---|
| `pwm` | `pwm_n_bit` | N-bit PWM generator with a duty deadband |
| `clamp` | `magnitude_clamp` | Combinational saturation of a signed command |
| `quad` | `decoder_to_32_bit` | Quadrature encoder decoder — a protocol, not a value |
| `ctrl` | `prop_ctrl_pwm` | The whole proportional loop, integrating the blocks above |

Out of scope, and unverified on purpose: `enel453_lab_initializer`, `debounce`,
`status_7seg`, and the ROM playback path.

### Logs

Every run writes to `sim/logs/`:

```
logs/xvlog.<phase>.log            compile
logs/xelab.<phase>.log            elaboration
logs/<phase>.<test>.<seed>.log    simulation
```

A run passed if the UVM report summary at the end of the simulation log shows no
`UVM_ERROR` or `UVM_FATAL`. Check it before believing an exit code.

### Waveforms

```sh
make WAVES=1                            # batch run, dumps logs/<phase>_<test>_<seed>.wdb
make gui                                # interactive, opens the XSim GUI
```

`WAVES=1` elaborates with `-debug typical` and runs `waves.tcl`, which decides what gets
dumped. Open a saved database later with:

```sh
xsim --gui logs/pwm_pwm_smoke_test_1.wdb
```

### Coverage

```sh
make COV=1 PHASE=pwm TEST=pwm_random_test SEED=1
make COV=1 PHASE=pwm TEST=pwm_random_test SEED=2
make cov                                # merge everything into cov_report/
```

Each `COV=1` run drops a database in `sim/xsim.covdb/` named
`<phase>_<test>_<seed>`; `make cov` merges whatever is there into an HTML report at
`sim/cov_report/index.html`. The `xcrg` flags differ between Vivado releases — if the merge
fails, `xcrg -help` is the place to look.

### Regressions

`sim/regress.py` is the seeded multi-test runner. **Not written yet** — it is an empty file
today.

### Cleaning up

```sh
make clean                              # build artifacts, logs, waveforms
make veryclean                          # also coverage databases and reports
```

---

## Current state

What actually runs today, on Vivado 2025.2:

- **UVM smoke test** — proves the UVM library elaborates and runs under XSim:

  ```sh
  cd sim && make PHASE=hello TOP=tb_hello TEST=hello_test
  ```

  Prints `UVM is alive on XSim` and exits. (`TOP` has to be given explicitly here because
  this top is named `tb_hello`, not `tb_hello_top`.)

- **`make PHASE=pwm`** — compiles and runs, but the stimulus is a hardcoded `initial`
  block in `tb/top/tb_pwm_top.sv`, not a UVM driver. `run_test()` is still commented out,
  so `TEST` is ignored. It exercises the DUT; it checks nothing.

Everything else is an empty file: all four agents, all four environments, all the test
packages, the assertion modules, and three of the five filelists. `PHASE=clamp`, `quad` and
`ctrl` will not build.

---

## Constraint strategy: items vs. sequences

Item classes (e.g. `tb/agents/pwm_agent/pwm_item.sv`) only constrain the basic necessities,
and do it with `soft` constraints:

```systemverilog
constraint c_range { soft duty inside {[0:(64'b1 << max_bits) - 1]}; }
constraint c_hold  { soft hold_periods inside {[1:4]}; }
```

`soft` is the point: it keeps a randomized item inside the DUT's bit width and inside a sane
default range if nothing else says otherwise, but it yields without conflict to whatever a
sequence asks for on the same field.

Sequences (`tb/sequences/*.sv`) are where stimulus actually gets shaped, via inline
constraints on the `randomize() with { ... }` call at each `start_item`/`finish_item`. For
example `pwm_base_seq` biases `duty` into boundary- and threshold-adjacent bins with a
`dist`, and `pwm_smoke_seq` pins it to specific edge values — neither has to fight the item's
own defaults to do it, because those defaults are soft.

---

## Repository layout

```
rtl/                    Device under test — vendored, see PROVENANCE.md
tb/
  common/               Interfaces, shared types, DUT golden-model functions
    sva/                Assertion modules, bound to the RTL without editing it
  agents/               One UVM agent per interface protocol
  env/                  Per-phase environments: agents + scoreboard + coverage
  tests/                Sequences and tests
  top/                  Per-phase testbench tops — clock, DUT, interface, run_test
sim/
  Makefile              The build; see `make help`
  filelists/            One compile filelist per phase
  regress.py            Seeded regression runner (not written yet)
  waves.tcl             What to dump when WAVES=1
```

Assertions live in separate modules attached with `bind`, so the RTL in `rtl/` stays
exactly as it synthesizes — no testbench code is ever added to a design file.
