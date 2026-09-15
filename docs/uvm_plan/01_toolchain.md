# Toolchain: XSim + UVM

Get this working before you write a line of testbench. Debugging "does my simulator support
UVM" and "is my driver wired correctly" at the same time is the fastest way to give up on
this project.

Everything in this file is build infrastructure. **Copy it — do not type it.** Typing a
Makefile teaches you nothing about verification.

---

## 1. What you already have

Verified on your machine:

| Thing | Location |
|---|---|
| Vivado 2025.2 | `~/Vivado/2025.2` |
| Simulator binaries | `~/Vivado/2025.2/Vivado/bin/{xvlog,xelab,xsim,xcrg}` |
| Precompiled UVM 1.2 for XSim | `~/Vivado/2025.2/data/xsim/system_verilog/uvm/uvm_1.2.rlx` |
| UVM macros header | `~/Vivado/2025.2/data/xsim/system_verilog/uvm_include/uvm_macros.svh` |
| UVM source (fallback) | `~/Vivado/2025.2/data/system_verilog/uvm_1.2/xlnx_uvm_package.sv` |
| Coverage report generator | `~/Vivado/2025.2/Vivado/bin/xcrg` |

You do not need to install anything. XSim's UVM support is real, and the precompiled library
means you do not pay UVM's compile time on every run.

### Environment setup

Add to `~/.bashrc`, or keep it in a `setup.sh` you source:

```bash
export XILINX_VIVADO="$HOME/Vivado/2025.2/Vivado"
export PATH="$XILINX_VIVADO/bin:$PATH"
```

Check it:

```bash
xvlog --version     # → Vivado Simulator v2025.2
```

> XSim's `xvlog`/`xelab`/`xsim` are standalone binaries. You do **not** need to source
> `settings64.sh` or launch the Vivado GUI to use them.

---

## 2. Repository layout

```
~/rotating-disk-uvm/
├── README.md
├── .gitignore
├── rtl/                        vendored copy of your design
│   ├── PROVENANCE.md           where it came from, which commit, when
│   ├── pwm_n_bit.sv
│   ├── magnitude_clamp.sv
│   ├── synchronizer.sv
│   ├── first_value_priority.sv
│   ├── directional_counter.sv
│   ├── decoder_to_32_bit.sv
│   ├── controller.sv
│   ├── clock_div.sv
│   ├── bar_encoder.sv
│   ├── led_status.sv
│   ├── status_7seg.sv
│   └── prop_ctrl_pwm.sv
├── tb/
│   ├── common/
│   │   ├── dut_pkg.sv          golden models — pure functions, no classes
│   │   ├── bufg_stub.sv
│   │   ├── pwm_if.sv
│   │   ├── clamp_if.sv
│   │   ├── quad_if.sv
│   │   ├── ctrl_if.sv
│   │   └── sva/
│   │       ├── pwm_n_bit_sva.sv
│   │       ├── magnitude_clamp_sva.sv
│   │       ├── first_value_priority_sva.sv
│   │       ├── controller_sva.sv
│   │       └── bind_all.sv
│   ├── agents/
│   │   ├── pwm_agent/          pwm_pkg.sv + item/driver/monitor/agent
│   │   ├── clamp_agent/
│   │   ├── quad_agent/
│   │   └── ctrl_agent/
│   ├── env/
│   │   ├── pwm_env_pkg.sv
│   │   ├── clamp_env_pkg.sv
│   │   ├── quad_env_pkg.sv
│   │   └── ctrl_env_pkg.sv
│   ├── tests/
│   │   ├── pwm_tests_pkg.sv
│   │   ├── clamp_tests_pkg.sv
│   │   ├── quad_tests_pkg.sv
│   │   └── ctrl_tests_pkg.sv
│   └── top/
│       ├── tb_hello.sv
│       ├── tb_pwm_top.sv
│       ├── tb_clamp_top.sv
│       ├── tb_quad_top.sv
│       └── tb_ctrl_top.sv
├── sim/
│   ├── Makefile
│   ├── filelists/{hello,pwm,clamp,quad,ctrl}.f
│   ├── regress.py
│   ├── waves.tcl
│   ├── logs/                   gitignored
│   └── run/                    gitignored
└── docs/
    ├── verification_plan.md
    ├── results.md
    └── coverage/               committed reports
```

### Why packages, not bare `` `include ``

Every group of classes lives in a SystemVerilog **package** compiled as one file, with the
class files pulled in by `` `include `` *inside* the package. That gives you:

- One compilation unit per logical group — far fewer ordering headaches.
- Explicit namespacing (`import pwm_agent_pkg::*;`).
- Filelists with four entries instead of forty.

The pattern:

```systemverilog
// tb/agents/pwm_agent/pwm_agent_pkg.sv
package pwm_agent_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import dut_pkg::*;

  `include "pwm_item.sv"
  `include "pwm_driver.sv"
  `include "pwm_monitor.sv"
  `include "pwm_agent.sv"
endpackage
```

The included files contain **only** the class definitions — no `import`, no `` `include ``,
no `package`. The include directory is added with `-i` in the filelist.

---

## 3. `.gitignore`

```gitignore
# XSim artifacts
xsim.dir/
*.wdb
*.jou
*.pb
*.str
webtalk*
xvlog.log
xelab.log
xsim.log
.Xil/

# Build outputs
sim/logs/
sim/run/
sim/xsim.covdb/
sim/cov_report/

# Python
__pycache__/
```

---

## 4. The smoke test — do this first

**`tb/top/tb_hello.sv`**

```systemverilog
`timescale 1ns/1ps

package hello_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class hello_test extends uvm_test;
    `uvm_component_utils(hello_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("HELLO", "UVM is alive on XSim", UVM_LOW)
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module tb_hello;
  import uvm_pkg::*;
  import hello_pkg::*;
  initial run_test("hello_test");
endmodule
```

**`sim/filelists/hello.f`**

```
../tb/top/tb_hello.sv
```

Run it by hand once, so you see the raw commands rather than only the Makefile's:

```bash
cd ~/rotating-disk-uvm/sim
xvlog -sv -L uvm -f filelists/hello.f
xelab -L uvm -timescale 1ns/1ps -s hello_snap tb_hello
xsim hello_snap -runall -testplusarg "UVM_TESTNAME=hello_test"
```

### What success looks like

```
----------------------------------------------------------------
UVM-1.2
(C) 2007-2014 Mentor Graphics Corporation
...
----------------------------------------------------------------
UVM_INFO @ 0: reporter [RNTST] Running test hello_test...
UVM_INFO tb_hello.sv(13) @ 0: uvm_test_top [HELLO] UVM is alive on XSim
UVM_INFO ... [UVM/REPORT/SERVER]
--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :    5
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

**If you see that, your toolchain is good and you can stop worrying about it.**

### Fallback if `-L uvm` misbehaves

The precompiled library is the fast path. If elaboration cannot find `uvm_pkg`, compile the
UVM source directly instead — slower (about 30 s), but always works:

```bash
xvlog -sv \
  -i $XILINX_VIVADO/../data/system_verilog/uvm_1.2 \
  $XILINX_VIVADO/../data/system_verilog/uvm_1.2/xlnx_uvm_package.sv
xvlog -sv -i $XILINX_VIVADO/../data/system_verilog/uvm_1.2 -f filelists/hello.f
xelab -timescale 1ns/1ps -s hello_snap tb_hello
```

Note the path: the binaries live in `$XILINX_VIVADO/bin`, but `data/` is one level up from
`$XILINX_VIVADO`, at `~/Vivado/2025.2/data`. Set a second variable if that annoys you:

```bash
export XILINX_ROOT="$HOME/Vivado/2025.2"
export XILINX_VIVADO="$XILINX_ROOT/Vivado"
```

Record which path worked in your README.

---

## 5. The `BUFG` stub

**`tb/common/bufg_stub.sv`**

```systemverilog
// Simulation-only stand-in for the Xilinx BUFG global clock buffer.
// The real primitive is a buffer with routing delay; functionally it is a wire.
// Used so the environment compiles with no Xilinx simulation libraries.
`timescale 1ns/1ps
module BUFG (input logic I, output logic O);
  assign O = I;
endmodule
```

Add it to the `quad` and `ctrl` filelists (any phase that pulls in `clock_div`).

**The alternative**, if you would rather use the real primitive:

```bash
xelab -L uvm -L unisims_ver -timescale 1ns/1ps -s ctrl_snap tb_ctrl_top glbl
# and compile $XILINX_ROOT/data/verilog/src/glbl.v alongside your sources
```

The stub is recommended: portable, no extra library, and the behavioural difference is nil
for functional verification. **Write the substitution into your README** so nobody reads
your results as a claim about silicon timing.

---

## 6. Filelists

XSim's `-f` files accept source paths, `-i <incdir>` and `-d <define>` lines, and `#`
comments. Keep one per phase.

**`sim/filelists/pwm.f`**

```
# ---- include directories (for `include inside packages) ----
-i ../tb/common
-i ../tb/agents/pwm_agent
-i ../tb/env
-i ../tb/tests

# ---- RTL ----
../rtl/pwm_n_bit.sv

# ---- TB common ----
../tb/common/dut_pkg.sv
../tb/common/pwm_if.sv
../tb/common/sva/pwm_n_bit_sva.sv

# ---- Agent / env / tests ----
../tb/agents/pwm_agent/pwm_agent_pkg.sv
../tb/env/pwm_env_pkg.sv
../tb/tests/pwm_tests_pkg.sv

# ---- Bind + top ----
../tb/common/sva/bind_all.sv
../tb/top/tb_pwm_top.sv
```

Order matters: packages must be compiled before anything that imports them. Interfaces
before the modules that use them. The top last.

**`sim/filelists/ctrl.f`** (Phase D — the full stack)

```
-i ../tb/common
-i ../tb/agents/pwm_agent
-i ../tb/agents/quad_agent
-i ../tb/agents/ctrl_agent
-i ../tb/env
-i ../tb/tests

../tb/common/bufg_stub.sv
../rtl/synchronizer.sv
../rtl/first_value_priority.sv
../rtl/directional_counter.sv
../rtl/decoder_to_32_bit.sv
../rtl/controller.sv
../rtl/magnitude_clamp.sv
../rtl/clock_div.sv
../rtl/pwm_n_bit.sv
../rtl/bar_encoder.sv
../rtl/led_status.sv
../rtl/status_7seg.sv
../rtl/prop_ctrl_pwm.sv

../tb/common/dut_pkg.sv
../tb/common/pwm_if.sv
../tb/common/quad_if.sv
../tb/common/ctrl_if.sv
../tb/common/sva/pwm_n_bit_sva.sv
../tb/common/sva/first_value_priority_sva.sv
../tb/common/sva/controller_sva.sv

../tb/agents/pwm_agent/pwm_agent_pkg.sv
../tb/agents/quad_agent/quad_agent_pkg.sv
../tb/agents/ctrl_agent/ctrl_agent_pkg.sv
../tb/env/ctrl_env_pkg.sv
../tb/tests/ctrl_tests_pkg.sv

../tb/common/sva/bind_all.sv
../tb/top/tb_ctrl_top.sv
```

---

## 7. The Makefile

**`sim/Makefile`**

```makefile
# =============================================================================
#  rotating-disk-uvm — XSim + UVM build
#
#  make PHASE=pwm TEST=pwm_random_test SEED=7            compile, elab, run
#  make PHASE=quad TEST=quad_dither_test WAVES=1 run     run and dump waves
#  make PHASE=ctrl gui                                   open the XSim GUI
#  make clean
# =============================================================================

XILINX_ROOT   ?= $(HOME)/Vivado/2025.2
XILINX_VIVADO ?= $(XILINX_ROOT)/Vivado
BIN           := $(XILINX_VIVADO)/bin

XVLOG := $(BIN)/xvlog
XELAB := $(BIN)/xelab
XSIM  := $(BIN)/xsim
XCRG  := $(BIN)/xcrg

# ---- knobs -------------------------------------------------------------
PHASE     ?= pwm
TEST      ?= $(PHASE)_smoke_test
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
WAVES     ?= 0
COV       ?= 0
TIMEOUT   ?= 20ms

TOP   := tb_$(PHASE)_top
SNAP  := $(PHASE)_snap
FLIST := filelists/$(PHASE).f
LOGS  := logs

# ---- flags -------------------------------------------------------------
XVLOG_FLAGS := -sv -L uvm --incr
XELAB_FLAGS := -L uvm --relax -timescale 1ns/1ps -s $(SNAP)
XSIM_FLAGS  := -runall -sv_seed $(SEED) \
               -testplusarg "UVM_TESTNAME=$(TEST)" \
               -testplusarg "UVM_VERBOSITY=$(VERBOSITY)" \
               -testplusarg "UVM_TIMEOUT=$(TIMEOUT)"

ifeq ($(WAVES),1)
  XELAB_FLAGS += -debug typical
  XSIM_FLAGS  := -tclbatch waves.tcl -wdb $(LOGS)/$(PHASE)_$(TEST)_$(SEED).wdb \
                 -sv_seed $(SEED) \
                 -testplusarg "UVM_TESTNAME=$(TEST)" \
                 -testplusarg "UVM_VERBOSITY=$(VERBOSITY)" \
                 -testplusarg "UVM_TIMEOUT=$(TIMEOUT)"
endif

ifeq ($(COV),1)
  XSIM_FLAGS += -cov_db_dir ./xsim.covdb -cov_db_name $(PHASE)_$(TEST)_$(SEED)
endif

.PHONY: all compile elab run gui cov clean veryclean help

all: run

$(LOGS):
	@mkdir -p $(LOGS)

compile: | $(LOGS)
	$(XVLOG) $(XVLOG_FLAGS) -f $(FLIST) -log $(LOGS)/xvlog.$(PHASE).log

elab: compile
	$(XELAB) $(XELAB_FLAGS) $(TOP) -log $(LOGS)/xelab.$(PHASE).log

run: elab
	$(XSIM) $(SNAP) $(XSIM_FLAGS) -log $(LOGS)/$(PHASE).$(TEST).$(SEED).log

gui: WAVES=1
gui: elab
	$(XSIM) $(SNAP) -gui \
	  -testplusarg "UVM_TESTNAME=$(TEST)" \
	  -testplusarg "UVM_VERBOSITY=$(VERBOSITY)"

# Merge whatever coverage databases exist into an HTML report.
# Flags vary between Vivado releases — run `$(XCRG) -help` and fix these once.
cov:
	$(XCRG) -dir ./xsim.covdb -report_format html -report_dir ./cov_report

clean:
	rm -rf xsim.dir $(LOGS) *.jou *.pb *.wdb .Xil webtalk*

veryclean: clean
	rm -rf xsim.covdb cov_report run

help:
	@echo "PHASE     = pwm | clamp | quad | ctrl      (default: pwm)"
	@echo "TEST      = UVM test class name           (default: <PHASE>_smoke_test)"
	@echo "SEED      = integer                       (default: 1)"
	@echo "VERBOSITY = UVM_LOW|UVM_MEDIUM|UVM_HIGH|UVM_DEBUG"
	@echo "WAVES     = 0 | 1                         dump a .wdb"
	@echo "COV       = 0 | 1                         collect coverage"
```

**`sim/waves.tcl`**

```tcl
log_wave -recursive *
run all
quit
```

---

## 8. Running things

```bash
cd ~/rotating-disk-uvm/sim

make PHASE=pwm TEST=pwm_smoke_test                    # first run
make PHASE=pwm TEST=pwm_random_test SEED=42           # a specific seed
make PHASE=pwm TEST=pwm_random_test SEED=42 VERBOSITY=UVM_HIGH
make PHASE=quad TEST=quad_dither_test WAVES=1         # dump waves
make PHASE=ctrl gui                                   # interactive
```

### Viewing a waveform after the fact

```bash
xsim --gui logs/quad_quad_dither_test_1.wdb
```

### Seeds and reproducibility

`-sv_seed <n>` makes a run exactly reproducible. `-sv_seed random` picks one and prints it.
**Always run with an explicit seed you record**, so that when a regression fails you can
reproduce it. A failure you cannot reproduce is a failure you cannot fix.

The seed is echoed in the log; grep for it if you used `random`.

---

## 9. Regression runner

**`sim/regress.py`**

```python
#!/usr/bin/env python3
"""Seeded regression for the rotating-disk UVM environment.

  ./regress.py                      # everything, 5 seeds each
  ./regress.py --phase quad         # one phase
  ./regress.py --seeds 20           # more seeds
  ./regress.py --test pwm_corner_test --seeds 50
"""
import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent

TESTS = {
    "pwm": [
        "pwm_smoke_test", "pwm_random_test", "pwm_corner_test",
        "pwm_duty_change_test", "pwm_reset_test",
    ],
    "clamp": [
        "clamp_smoke_test", "clamp_random_test", "clamp_corner_test",
    ],
    "quad": [
        "quad_smoke_test", "quad_forward_test", "quad_reverse_test",
        "quad_reversal_test", "quad_dither_test", "quad_fast_test",
        "quad_random_test",
    ],
    "ctrl": [
        "ctrl_smoke_test", "ctrl_random_test", "ctrl_convergence_test",
        "ctrl_gain_sweep_test", "ctrl_slow_test",
    ],
}

SEV = re.compile(r"^UVM_(INFO|WARNING|ERROR|FATAL)\s*:\s*(\d+)", re.M)


def run_one(phase, test, seed, cov):
    cmd = ["make", "-s", f"PHASE={phase}", f"TEST={test}", f"SEED={seed}", "run"]
    if cov:
        cmd.append("COV=1")
    t0 = time.time()
    p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    elapsed = time.time() - t0
    out = p.stdout + p.stderr

    counts = {k: int(v) for k, v in SEV.findall(out)}
    saw_summary = "UVM Report Summary" in out

    if p.returncode != 0:
        status = "TOOLFAIL"
    elif not saw_summary:
        status = "NOSUMMARY"      # crashed, hung, or never ran the test
    elif counts.get("FATAL", 0) or counts.get("ERROR", 0):
        status = "FAIL"
    else:
        status = "PASS"

    return status, counts, elapsed, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=list(TESTS), action="append")
    ap.add_argument("--test")
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--start-seed", type=int, default=1)
    ap.add_argument("--cov", action="store_true")
    args = ap.parse_args()

    phases = args.phase or list(TESTS)
    rows, failures = [], []

    for phase in phases:
        tests = [args.test] if args.test else TESTS[phase]
        for test in tests:
            for seed in range(args.start_seed, args.start_seed + args.seeds):
                status, counts, elapsed, out = run_one(phase, test, seed, args.cov)
                rows.append((phase, test, seed, status,
                             counts.get("ERROR", 0), counts.get("WARNING", 0), elapsed))
                mark = "." if status == "PASS" else "X"
                print(mark, end="", flush=True)
                if status != "PASS":
                    failures.append((phase, test, seed, status, out))
    print("\n")

    w = max(len(r[1]) for r in rows)
    print(f"{'PHASE':<6} {'TEST':<{w}} {'SEED':>5} {'STATUS':<10} {'ERR':>4} {'WARN':>5} {'TIME':>7}")
    print("-" * (6 + w + 5 + 10 + 4 + 5 + 7 + 6))
    for phase, test, seed, status, err, warn, elapsed in rows:
        print(f"{phase:<6} {test:<{w}} {seed:>5} {status:<10} {err:>4} {warn:>5} {elapsed:>6.1f}s")

    npass = sum(1 for r in rows if r[3] == "PASS")
    print(f"\n{npass}/{len(rows)} passed")

    for phase, test, seed, status, out in failures:
        print(f"\n{'=' * 70}\nFAILURE: {phase} {test} seed={seed} ({status})")
        print(f"  reproduce: make PHASE={phase} TEST={test} SEED={seed} VERBOSITY=UVM_HIGH run")
        print("-" * 70)
        for line in out.splitlines():
            if "UVM_ERROR" in line or "UVM_FATAL" in line:
                print("  " + line)

    return 0 if npass == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
```

`chmod +x regress.py`. It compiles once per invocation of `make` — slightly wasteful, but
`--incr` on `xvlog` makes repeat compiles cheap, and correctness beats cleverness in a
regression script.

> **On parallelism:** XSim writes its work library into `xsim.dir/` in the current directory,
> so running several seeds concurrently from the same directory will corrupt each other.
> Keep the regression serial to start. If runtime becomes painful, the fix is a per-seed run
> directory with a symlink to a shared `xsim.dir`, not `make -j`.

---

## 10. Coverage

XSim collects covergroup data when you pass a coverage database directory, and `xcrg` merges
and reports it:

```bash
make PHASE=pwm TEST=pwm_random_test SEED=1 COV=1 run
make PHASE=pwm TEST=pwm_corner_test SEED=1 COV=1 run
make cov          # → sim/cov_report/index.html
```

**These flags move between Vivado releases.** Before you rely on them, run:

```bash
xsim -help  | grep -i cov
xcrg -help
```

and fix the Makefile once against what your 2025.2 actually accepts. Then **write the working
command into your README** — future-you and anyone reading the repo will want it. If the
flow proves fragile, the fallback is to have your coverage subscriber print
`$get_coverage()` at `report_phase` and record the numbers manually; less pretty, entirely
legitimate, and worth mentioning as a known limitation.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: [VRFC 10-3182] unit uvm_pkg not found` | `-L uvm` missing on `xvlog` **or** `xelab` | Both need it. |
| `` `uvm_macros.svh` not found `` | Include path not picked up | `-L uvm` normally supplies it; otherwise add `-i $XILINX_ROOT/data/system_verilog/uvm_1.2`. |
| `cannot find module BUFG` | `clock_div` pulled in without the stub | Add `bufg_stub.sv` to the filelist (first). |
| Simulation ends at time 0, test "passes" | No objection was raised | `phase.raise_objection(this)` at the top of `run_phase`. `tutorials/T3`. |
| Simulation never ends | An objection was raised and never dropped | Every raise needs a matching drop, including on early-exit paths. `tutorials/T3`. |
| `UVM_FATAL ... virtual interface not set` | `config_db` set/get path or type mismatch | Types must match exactly (`virtual pwm_if` ≠ `virtual pwm_if.DRV`). `tutorials/T4`. |
| Driver gets no items | Sequence not started on the right sequencer, or agent is passive | `seq.start(env.agent.sequencer)`; check `is_active`. |
| Scoreboard is consistently one item behind | Driver/monitor sampling race | Use clocking blocks on both sides. `tutorials/T1`. |
| Everything is `x` for the first cycles | `synchronizer` has no reset (O-QUAD-4) | `disable iff` + a settle window after reset. |
| `logic [-1:0]` elaboration error | `$clog2(TICKS)` with `TICKS <= 1` (O-DIV-1) | Fix the parameter; add the guard assertion. |
| Two runs with the same seed differ | Something is reading `$time` or `$random` outside the seeded stream | Use `randomize()` for all randomness; never `$random`. |
| Compile is slow every time | Not using `--incr` | Already in the Makefile; check `xsim.dir/` is not being cleaned. |
| `xelab` complains about a construct that looks legal | XSim strictness | `--relax` is already in `XELAB_FLAGS`. If it persists, it is probably a real error. |

### Reading a UVM failure

```
UVM_ERROR tb/env/pwm_scoreboard.sv(58) @ 41000: uvm_test_top.env.sb [PWM_SB]
          duty=137 expected high=122 observed=121
```

Left to right: severity, source location, simulation time, **component path**, message ID,
message. The component path is the useful part — it tells you exactly which instance
complained, which matters once you have two agents of the same type.

Turn the verbosity up on a failing seed only:

```bash
make PHASE=pwm TEST=pwm_random_test SEED=42 VERBOSITY=UVM_HIGH run
```

More in `tutorials/T10_debugging_xsim.md`.
