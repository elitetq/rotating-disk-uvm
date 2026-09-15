# T10 — Debugging UVM Under XSim

**Reference.** Come back to this when something is wrong.

---

## Verbosity

```bash
make PHASE=pwm TEST=pwm_random_test SEED=42 VERBOSITY=UVM_HIGH run
```

| Level | Use |
|---|---|
| `UVM_NONE` | errors only |
| `UVM_LOW` | phase banners, summaries — **default for regressions** |
| `UVM_MEDIUM` | transaction-level activity |
| `UVM_HIGH` | per-item detail from drivers and monitors |
| `UVM_DEBUG` | everything, including UVM internals. Noisy. |

Write your `uvm_info` calls at the right level from the start:

```systemverilog
  `uvm_info("DRV", $sformatf("duty=%0d", item.duty), UVM_HIGH)     // per item
  `uvm_info("SB",  $sformatf("checked %0d", n_checked), UVM_LOW)   // per test
```

Then a regression stays readable and one failing seed can be re-run loud.

### Per-component verbosity

```systemverilog
  env.agent.driver.set_report_verbosity_level(UVM_HIGH);
```

Turn up one component instead of drowning in the whole environment.

---

## Reading a UVM message

```
UVM_ERROR tb/env/pwm_scoreboard.sv(58) @ 41000: uvm_test_top.env.sb [PWM_SB]
          duty=137 expected high=122 observed=121
```

`severity | file(line) | @time | component path | ID | message`

The **component path** is the part people skip and the part that matters — it names the exact
instance, which is what you need once two agents of the same type exist.

The **ID** (`PWM_SB`) is greppable. Use consistent, distinct IDs per component.

---

## The topology print

```systemverilog
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
```

Prints the whole component tree with instance paths. Leave it in during development — it is
the fastest way to see what your `config_db` scope strings must match, and to notice a
component that was never created.

`factory.print()` in the same phase lists registered types and active overrides.

---

## Waveforms

```bash
make PHASE=quad TEST=quad_dither_test SEED=3 WAVES=1 run
xsim --gui logs/quad_quad_dither_test_3.wdb
```

`WAVES=1` adds `-debug typical` to elaboration and runs `waves.tcl`
(`log_wave -recursive *`). That logs everything, which is slow on long tests — for a targeted
dump, write a narrower tcl:

```tcl
log_wave -recursive [get_objects /tb_quad_top/DUT/*]
log_wave [get_objects /tb_quad_top/vif/*]
run all
quit
```

**Class objects do not appear in waveforms.** UVM transactions are dynamic objects with no
hierarchy; the waveform shows pins. Correlate by simulation time: find the `uvm_error`
timestamp in the log, then go to that time in the waveform.

---

## Symptom → cause

| Symptom | Likely cause | Where |
|---|---|---|
| Ends at time 0, reports pass | No objection raised | T3 |
| Never ends | Objection never dropped | T3 |
| `null object access` fatal | Handle declared, never `create`d — usually a missing `build_phase` line | T2 |
| `virtual interface not set` | `config_db` type or scope mismatch | T4 |
| Driver receives nothing | Sequence not started on that sequencer, or agent is passive | T6 |
| Scoreboard one item behind | Driver/monitor race — missing clocking block | T1 |
| Passes with `WAVES=0`, fails with `WAVES=1` | Same race. The dump perturbed scheduling. | T1 |
| Scoreboard checked 0 items, reports pass | Missing drain time, or nothing connected | T3, T6 |
| Coverage stuck at 0% | Covergroup never constructed, or `sample()` never called | T9 |
| Assertion fires constantly at reset | Missing `disable iff (reset)` | T8 |
| Assertion fires at time 0 only | `x` propagation from an unreset flop | T8, O-QUAD-4 |
| `randomize()` returns 0 | Over-constrained | T7 |
| Same seed, different results | `$random` used somewhere, or a race | T7 |
| `unit uvm_pkg not found` | `-L uvm` missing on `xvlog` or `xelab` | `01_toolchain.md` |
| `cannot find module BUFG` | Stub missing from filelist | `01_toolchain.md` |
| `logic [-1:0]` elaboration error | `$clog2(TICKS)` with `TICKS <= 1` | O-DIV-1 |

---

## Bisecting a failure

When a random test fails and you cannot see why:

1. **Reproduce it.** `SEED=<n>`. If it does not reproduce, fix the non-determinism first —
   nothing else is worth doing until then.
2. **Shrink it.** Reduce the item count until it still fails. A failure at item 3 is
   tractable; at item 847 it is not.
3. **Turn up verbosity** on the failing seed only.
4. **Dump waves** and go to the error timestamp.
5. **Suspect the testbench first** for Phases A–C. Your RTL has run on hardware; your
   scoreboard has run for a day.
6. **Check the golden model in isolation** — call it from a plain `initial` block with the
   failing inputs. Half the time the model is wrong.

---

## Assertions on your own testbench

Worth repeating from T8: assertions that check *stimulus legality* save real time.

```systemverilog
  a_single_channel: assert property (
    @(posedge clk) disable iff (reset) !($changed(ch_a) && $changed(ch_b))
  ) else `uvm_error("TB", "driver produced an illegal quadrature transition");
```

Without it, a driver bug presents as a DUT bug.

---

## XSim-specific notes

- **`--incr`** on `xvlog` makes repeat compiles much faster. Already in the Makefile.
- **`--relax`** on `xelab` loosens some strictness. Already there. If an error survives it,
  it is probably real.
- **`-testplusarg`** is XSim's way to pass `+plusargs`:
  `-testplusarg "UVM_TESTNAME=my_test"`. Not `+UVM_TESTNAME=...` on the command line.
- **UVM_TIMEOUT** as a plusarg works, but `uvm_top.set_timeout()` in code is more reliable
  across versions.
- **Class debugging in the GUI is limited.** XSim's class-object inspection is weaker than
  commercial tools. Lean on `uvm_info` and `print()` more than you would elsewhere — it is a
  real constraint of the free toolchain, not a gap in your technique.
- **`xsim.dir/` is per-directory.** Running two simulations concurrently from the same
  directory corrupts the work library. Keep the regression serial.

---

## Further reading

- Xilinx UG900 — *Vivado Design Suite User Guide: Logic Simulation* (the XSim reference)
- UVM 1.2 User's Guide, ch. 3 (the reporting system)
- Verification Academy — UVM Debug cookbook
