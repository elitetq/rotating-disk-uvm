# Phase A — `pwm_n_bit`

**Goal:** get every UVM moving part working, on a DUT so simple that when something breaks
you know it is the testbench.

**Not the goal:** verifying `pwm_n_bit` thoroughly. That is a side effect.

**Time:** about a week. **Prerequisite:** Step 0 complete — the smoke test runs.

> Phase A gives you the most complete skeletons in this guide. Later phases give
> progressively less, because by Phase C you should be writing components from the shape in
> your head. If Phase A feels like a lot of hand-holding, good — that is where the plumbing
> is learned.

**Read first:** `tutorials/T1` (interfaces and clocking blocks), `T2` (classes),
`T3` (phases and objections), `T4` (config_db).

---

## The DUT

```systemverilog
module pwm_n_bit #(parameter int BITS = 12, parameter int THRESHOLD = 0) (
    input  logic            clk, reset,
    input  logic [BITS-1:0] duty,
    output logic            pwm_out
);
```

Golden model, derived in `02_design_under_test.md` §1:

```
high_cycles(duty) = (duty > THRESHOLD) ? duty + 1 : 0     per 2**BITS-clock period
```

Phase A uses `BITS = 8, THRESHOLD = 14` — the configuration `top_module` actually builds.

> **`rtl/pwm_n_bit.sv` diverges from upstream here, deliberately** — see
> `rtl/PROVENANCE.md` §2. Upstream's relation is `(Q < duty) && (Q > THRESHOLD)`, giving
> `max(0, duty − THRESHOLD − 1)`. Every number in this chapter follows the vendored copy in
> `rtl/`, which is what you actually simulate. If the two ever disagree, `rtl/` wins and
> this chapter is stale — fix the chapter, never bend the golden model to match the prose.

---

## A design decision to make before you start

**Interfaces in this project are unparameterized, with generous fixed widths.**

The tempting alternative is `interface pwm_if #(parameter int BITS = 8)`. Do not. A
parameterized interface makes the virtual interface type parameterized too
(`virtual pwm_if#(8)`), and every class that holds one has to name the same parameter value
at compile time. The moment you want to run the same environment at two widths — which
Phase B explicitly requires — you are stuck.

The standard fix: make the interface wide enough for any configuration, and pass the actual
width through `uvm_config_db` as a plain `int`. Slightly wasteful in signal bits, completely
free in simulation, and it keeps every class width-agnostic.

You will find this genuinely useful in Phase B and Phase D. It is also a good answer to
"tell me about a testbench architecture decision you made."

---

## Step A1 — Interface and TB top

### `tb/common/pwm_if.sv`

```systemverilog
// Pin-level connection between the PWM agent and pwm_n_bit.
//
// Unparameterized on purpose (see 04_phase_a_pwm.md): MAX_BITS is wide enough
// for any configuration we test, and the real width arrives via config_db.
interface pwm_if (input logic clk);

  localparam int MAX_BITS = 16;

  logic                reset;
  logic [MAX_BITS-1:0] duty;
  logic                pwm_out;

  // Driver's view. Outputs are driven a little AFTER the clock edge; inputs are
  // sampled a little BEFORE it. That skew is what stops the driver and the DUT
  // from racing in the same simulation timestep. See tutorials/T1.
  clocking drv_cb @(posedge clk);
    default input #1step output #1ns;
    output reset, duty;
    input  pwm_out;
  endclocking

  // Monitor's view. Everything is an input, sampled just before the edge, so the
  // monitor sees the same values the DUT's flops did.
  clocking mon_cb @(posedge clk);
    default input #1step;
    input reset, duty, pwm_out;
  endclocking

  modport DRV (clocking drv_cb);
  modport MON (clocking mon_cb);

endinterface
```

**Why `#1step` and `#1ns`?** `1step` means "sample in the preponed region, before any
nonblocking assignment updates this timestep" — the same instant the DUT's own flops sample.
`#1ns` on outputs means the driver's value lands after the edge, so the DUT never sees it in
the same cycle it was driven. Get this wrong and your scoreboard will be off by one item in
a way that looks like a logic bug. `tutorials/T1` shows the failure explicitly, and Phase B
has you reproduce it on purpose.

### `tb/top/tb_pwm_top.sv`

```systemverilog
`timescale 1ns/1ps

module tb_pwm_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import pwm_tests_pkg::*;

  localparam int  BITS       = 8;
  localparam int  THRESHOLD  = 14;
  localparam time CLK_PERIOD = 10ns;      // 100 MHz

  logic clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  pwm_if vif (.clk(clk));

  pwm_n_bit #(.BITS(BITS), .THRESHOLD(THRESHOLD)) DUT (
    .clk     (clk),
    .reset   (vif.reset),
    .duty    (vif.duty[BITS-1:0]),        // narrow the wide interface bus
    .pwm_out (vif.pwm_out)
  );

  initial begin
    uvm_config_db#(virtual pwm_if)::set(null, "*", "vif",       vif);
    uvm_config_db#(int)::set          (null, "*", "BITS",       BITS);
    uvm_config_db#(int)::set          (null, "*", "THRESHOLD",  THRESHOLD);
    run_test();                            // test name comes from +UVM_TESTNAME
  end

endmodule
```

### Gate A1

**First, make it compile.** The top above is the *finished* Phase A top, and it will not
build yet — `import pwm_tests_pkg::*;` names a package you do not write until Step A4:

```
ERROR: [VRFC 10-2989] 'pwm_tests_pkg' is not declared [tb/top/tb_pwm_top.sv:7]
ERROR: [VRFC 10-8530] module 'tb_pwm_top' is ignored due to previous errors
```

`xelab` then fails with `Cannot find design unit work.tb_pwm_top`, which is the same error
one stage later, not a second problem. Comment out **both** the import and the `run_test()`
block for this gate:

```systemverilog
  // import pwm_tests_pkg::*;                 // GATE A1 ONLY — restore at Step A4
  ...
  // initial begin
  //   uvm_config_db#(virtual pwm_if)::set(null, "*", "vif", vif);
  //   ...
  //   run_test();
  // end
```

An empty stub package is not a shortcut: the Makefile always passes
`UVM_TESTNAME=pwm_smoke_test`, so `run_test()` would `UVM_FATAL` at time 0 and you would get
no waveform at all. Restore both at Step A4, when `pwm_tests_pkg` first has content.

Now prove the DUT and the interface are wired correctly. Temporarily add:

```systemverilog
  initial begin
    vif.reset = 1; vif.duty = 0;
    repeat (5) @(posedge clk);
    vif.reset = 0;
    vif.duty  = 100;
    repeat (3 * 2**BITS) @(posedge clk);
    $finish;
  end
```

Run it and look at `pwm_out`:

```bash
make PHASE=pwm WAVES=1 run
```

`duty = 100` clears the deadband (`100 > 14`), so `pwm_out` should be high for
`100 + 1 = 101` cycles out of every 256, in **one contiguous run starting at `Q = 0`**.
**Count them in the waveform.** If that does not match, stop — nothing built on top will be
right.

Two wrong answers are worth recognising on sight:

| What you count | What it means |
|---:|---|
| **85** | You are simulating *upstream* RTL, not the vendored copy — `rtl/pwm_n_bit.sv` has been reverted or re-synced. Check `rtl/PROVENANCE.md` §2. |
| **0** | `duty` never reached the DUT. Usually the `vif.duty[BITS-1:0]` narrowing, or reset still asserted. |

Delete the temporary stimulus block. Leave the import and `run_test()` commented until
Step A4. Commit.

---

## Step A2 — The golden model

This is a **pure function in a package**. No classes. It is the single most reused piece of
the whole environment: the scoreboard calls it, the coverage model can call it, and you can
call it from a plain `initial` block to sanity-check it.

### `tb/common/dut_pkg.sv`

```systemverilog
// Golden models for the rotating-disk design.
// Pure functions only — no classes, no state, no UVM dependency.
// Every function here is derived in uvm_plan/02_design_under_test.md.
package dut_pkg;

  // ------------------------------------------------------------------
  // pwm_n_bit  (02_design_under_test.md §1)
  //
  //   pwm_out is high exactly while  duty > THRESHOLD  and  Q <= duty,
  //   so Q spans the closed range [0, duty] — duty+1 counts — or nothing at all.
  //
  //   high_cycles = (duty > THRESHOLD) ? duty + 1 : 0   per 2**BITS clocks
  // ------------------------------------------------------------------
  function automatic int expected_pwm_high(input int duty, input int threshold);
    // TODO(you): one line.
    // Careful on two counts: the deadband test is on `duty`, NOT on Q; and mind
    // the +1 — a command of `duty` produces `duty + 1` high cycles, not `duty`.
  endfunction

  function automatic int pwm_period(input int bits);
    // TODO(you): the period in clk_divd cycles. One line.
  endfunction

endpackage
```

### Gate A2

Write a throwaway module that imports `dut_pkg` and prints
`expected_pwm_high(d, 14)` for `d ∈ {0, 1, 14, 15, 16, 100, 254, 255}`. Compare against the
table in `02_design_under_test.md` §1: `0, 0, 0, 16, 17, 101, 255, 256`.

Note that `d = 255` gives `256` — a full period, exactly 100% duty. That is correct, and it
is the entire point of the R-PWM-4 change recorded in `rtl/PROVENANCE.md` §2. Since
`pwm_period(8)` also returns 256, `high_cycles == period` is a legal, reachable state: make
sure neither your monitor nor your scoreboard treats it as an error or an overflow.

**Do not skip this.** A wrong golden model produces a scoreboard that fails on correct RTL,
and you will spend a day blaming the DUT. Twenty lines now saves that day.

---

## Step A3 — The sequence item

The smallest class in UVM: a bag of randomizable fields describing one unit of stimulus.

### `tb/agents/pwm_agent/pwm_item.sv`

```systemverilog
class pwm_item extends uvm_sequence_item;

  rand bit [15:0] duty;
  rand int unsigned hold_periods;    // how many full PWM periods to hold this duty

  // Field macros give you print / copy / compare / pack for free.
  // Writing those methods by hand is exactly the OOP busywork we are avoiding.
  `uvm_object_utils_begin(pwm_item)
    `uvm_field_int(duty,         UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(hold_periods, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pwm_item");
    super.new(name);
  endfunction

  // TODO(you): constrain hold_periods to something sane — 1 to 3.
  //            A test that holds each duty for 200 periods is a slow test that
  //            checks nothing extra.
  constraint c_hold { }

  // TODO(you): constrain duty to the legal range for the configured width.
  //            Problem: this class does not know BITS. Two options —
  //              (a) a non-rand `int max_duty` field the sequence sets before
  //                  randomize(), with `constraint c_range { duty <= max_duty; }`
  //              (b) an inline constraint at the call site:
  //                  `item.randomize() with { duty <= (1<<bits)-1; }`
  //            Pick one and write down why. (a) keeps the knowledge in the item;
  //            (b) keeps the item dumb. Both are defensible; (a) scales better.
  constraint c_range { }

endclass
```

### Gate A3

From a temporary `initial` block:

```systemverilog
pwm_item it = pwm_item::type_id::create("it");
repeat (5) begin
  void'(it.randomize());
  it.print();
end
```

You should see five items with sensible values. If `randomize()` returns 0, a constraint is
unsatisfiable — print `it.duty.rand_mode()` or comment constraints out one at a time.

---

## Step A4 — Driver, sequencer, sequence, test

Four pieces at once, because none of them does anything alone. Still no monitor, no
scoreboard — this step only proves that stimulus reaches the pins.

### `tb/agents/pwm_agent/pwm_driver.sv`

```systemverilog
class pwm_driver extends uvm_driver #(pwm_item);

  `uvm_component_utils(pwm_driver)

  virtual pwm_if vif;
  int unsigned   bits;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pwm_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"virtual interface not set for ", get_full_name()})
    if (!uvm_config_db#(int)::get(this, "", "BITS", bits))
      `uvm_fatal("NOCFG", "BITS not set")
  endfunction

  task run_phase(uvm_phase phase);
    // TODO(you): put the pins in a known state before the first item arrives.
    //   Drive reset high for a few cycles, duty to 0, then release reset.
    //   Hint: @(vif.drv_cb) advances exactly one clock.
    //   Hint: assign through the clocking block —  vif.drv_cb.reset <= 1'b1;
    //         NOT  vif.reset = 1'b1;  (that bypasses the skew and races the DUT)

    forever begin
      seq_item_port.get_next_item(req);   // blocks until the sequencer has one
      drive(req);
      seq_item_port.item_done();          // tells the sequencer we are ready for more
    end
  endtask

  task drive(pwm_item item);
    // TODO(you):
    //   1. Drive item.duty onto vif.drv_cb.duty
    //   2. Wait item.hold_periods * 2**bits clock edges, so the monitor sees
    //      whole periods at this duty and never a mixture of two.
    //   Hint: repeat (N) @(vif.drv_cb);
    //   `uvm_info("DRV", $sformatf("driving duty=%0d for %0d periods",
    //             item.duty, item.hold_periods), UVM_HIGH)
  endtask

endclass
```

**On `get_next_item` / `item_done`:** this pair is the driver–sequencer handshake. The
sequencer holds items produced by sequences; the driver pulls one, converts it to pin
activity, and signals completion. Nothing happens until a sequence is started on that
sequencer. `tutorials/T6` has the full picture.

### `tb/agents/pwm_agent/pwm_agent.sv`

The sequencer needs no body at all:

```systemverilog
typedef uvm_sequencer #(pwm_item) pwm_sequencer;

class pwm_agent extends uvm_agent;

  `uvm_component_utils(pwm_agent)

  pwm_driver    driver;
  pwm_sequencer sequencer;
  pwm_monitor   monitor;

  uvm_analysis_port #(pwm_obs) ap;    // re-published from the monitor

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap      = new("ap", this);
    monitor = pwm_monitor::type_id::create("monitor", this);

    // is_active comes from uvm_agent; the env sets it via config_db.
    // A PASSIVE agent has a monitor only — which is exactly what Phase D needs
    // when it reuses this agent to watch the PWM output inside prop_ctrl_pwm.
    if (get_is_active() == UVM_ACTIVE) begin
      driver    = pwm_driver::type_id::create("driver", this);
      sequencer = pwm_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    monitor.ap.connect(ap);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass
```

**Build this active/passive split now, even though Phase A never uses passive mode.** Phase D
reuses this exact agent in passive mode to observe `motor_en` inside `prop_ctrl_pwm`. Bolting
it on later means editing a component you had already declared finished — and "I designed
the agent so it could be reused passively at the subsystem level" is a much better sentence
than "I copied it and deleted the driver."

### `tb/tests/pwm_seq_lib.sv`

```systemverilog
class pwm_base_seq extends uvm_sequence #(pwm_item);
  `uvm_object_utils(pwm_base_seq)

  int unsigned n_items = 20;
  int unsigned bits    = 8;

  function new(string name = "pwm_base_seq");
    super.new(name);
  endfunction

  task body();
    // TODO(you): repeat n_items times:
    //   req = pwm_item::type_id::create("req");
    //   start_item(req);
    //   if (!req.randomize() with { /* ... */ }) `uvm_error(...)
    //   finish_item(req);
    //
    // start_item blocks until the driver is ready; finish_item hands it over.
    // Randomizing BETWEEN them is the idiom — it means the constraint solver runs
    // as late as possible, so a sequence can react to what already happened.
  endtask
endclass
```

Then subclasses that only change the constraint:

```systemverilog
class pwm_corner_seq extends pwm_base_seq;
  `uvm_object_utils(pwm_corner_seq)
  function new(string name = "pwm_corner_seq"); super.new(name); endfunction

  task body();
    // TODO(you): walk a fixed list of interesting duties instead of randomizing:
    //   {0, 1, THRESHOLD, THRESHOLD+1, THRESHOLD+2, max-1, max}
    // Directed stimulus inside a UVM sequence is completely legitimate.
    // Random is a tool, not a religion.
  endtask
endclass
```

### `tb/tests/pwm_base_test.sv`

```systemverilog
class pwm_base_test extends uvm_test;

  `uvm_component_utils(pwm_base_test)

  pwm_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = pwm_env::type_id::create("env", this);
  endfunction

  // Useful and cheap: dump the whole component tree once, so you can see the
  // instance paths your config_db calls need to match.
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    pwm_base_seq seq;
    phase.raise_objection(this);          // "do not end the sim yet"
    // TODO(you): create the sequence, set its knobs, start it on
    //            env.agent.sequencer, then wait a few periods for the last
    //            item to drain out of the monitor.
    phase.drop_objection(this);           // "done"
  endtask

endclass
```

**The objection pair is the single most common beginner failure.** No raise and the
simulation ends at time 0 with a cheerful pass. No drop and it runs forever. `tutorials/T3`.

### Gate A4

```bash
make PHASE=pwm TEST=pwm_base_test VERBOSITY=UVM_HIGH run
```

You should see the topology print, then one `[DRV] driving duty=...` line per item, then a
report summary with zero errors. Open the waveform and confirm `duty` changes as logged.

**No checking has happened yet.** That is fine. Commit.

---

## Step A5 — The monitor

The monitor observes pins and publishes transactions. It must never drive anything, and it
must work whether or not a driver exists — that is what makes passive reuse possible.

### The observation type

```systemverilog
class pwm_obs extends uvm_sequence_item;
  int unsigned duty;
  int unsigned high_cycles;
  int unsigned period_cycles;

  `uvm_object_utils_begin(pwm_obs)
    `uvm_field_int(duty,          UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(high_cycles,   UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(period_cycles, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pwm_obs"); super.new(name); endfunction
endclass
```

Keeping the observation type separate from the stimulus type is a deliberate choice: they
carry different information (the driver never knows `high_cycles`), and conflating them is
how scoreboards end up with half-filled objects.

### `tb/agents/pwm_agent/pwm_monitor.sv`

```systemverilog
class pwm_monitor extends uvm_monitor;

  `uvm_component_utils(pwm_monitor)

  virtual pwm_if vif;
  int unsigned   bits;

  uvm_analysis_port #(pwm_obs) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO(you): get vif and BITS from config_db, uvm_fatal if missing
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      // TODO(you):
      //  1. Wait for reset to deassert.
      //  2. Establish a period boundary (see the decision below).
      //  3. Over exactly 2**bits clocks, count the cycles where pwm_out is high,
      //     and capture the duty in effect.
      //  4. Build a pwm_obs and ap.write(obs).
      //
      // Hint: sample through the clocking block — vif.mon_cb.pwm_out — never
      //       the raw signal. Raw sampling races the DUT.
    end
  endtask

endclass
```

### The decision this step is really about

**How does the monitor know where a PWM period starts?** `Q` is internal to the DUT; from
the pins you cannot see it. Three answers, all used in real environments:

| Approach | How | Trade-off |
|---|---|---|
| **Count from reset** | After reset deasserts, `Q = 0` and increments every clock. Period boundaries are at multiples of `2**BITS` clocks from there. | Pure black-box. Breaks if reset is reasserted mid-test — so handle that. **Recommended.** |
| **White-box probe** | `bind` a probe module into `pwm_n_bit` and watch `Q == 0`, or use a hierarchical reference `tb_pwm_top.DUT.Q`. | Simple and robust. But now the monitor depends on the DUT's internal names, so an RTL refactor breaks the testbench. |
| **Infer from the output** | Detect the rising edge of `pwm_out` and measure to the next one. | Fails entirely when `duty` is in the deadband and `pwm_out` never rises. |

Pick one, implement it, and **write down in your notes why**. This is a real testbench
architecture decision with a real trade-off, and being able to talk about it is worth more
than the twenty lines of code it costs.

### Gate A5

Add a temporary subscriber that just prints each `pwm_obs`. Run the smoke sequence and
compare the printed `high_cycles` against the waveform, by hand, for three items.

---

## Step A6 — The scoreboard

### `tb/env/pwm_scoreboard.sv`

```systemverilog
class pwm_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(pwm_scoreboard)

  uvm_analysis_imp #(pwm_obs, pwm_scoreboard) ap_imp;

  int unsigned threshold;
  int          n_checked;
  int          n_failed;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_imp = new("ap_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO(you): get THRESHOLD from config_db
  endfunction

  // Called automatically for every transaction written to the connected analysis port.
  function void write(pwm_obs obs);
    // TODO(you):
    //   int exp = dut_pkg::expected_pwm_high(obs.duty, threshold);
    //   n_checked++;
    //   if (obs.high_cycles != exp) begin n_failed++; `uvm_error(...) end
    //   else `uvm_info("SB", ..., UVM_HIGH)
    //
    // Put duty, expected and observed in the error message. A message that says
    // only "mismatch" costs you ten minutes every time it fires.
  endfunction

  function void report_phase(uvm_phase phase);
    // TODO(you): print n_checked / n_failed.
    //
    // AND — this matters — raise a uvm_error if n_checked == 0.
    // A scoreboard that checked nothing reports a clean pass, and a clean pass
    // that checked nothing is the most dangerous result in verification.
    // Guard against it explicitly, in every scoreboard you ever write.
  endfunction

endclass
```

### `tb/env/pwm_env.sv`

```systemverilog
class pwm_env extends uvm_env;

  `uvm_component_utils(pwm_env)

  pwm_agent      agent;
  pwm_scoreboard sb;
  pwm_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
    agent = pwm_agent::type_id::create("agent", this);
    sb    = pwm_scoreboard::type_id::create("sb",  this);
    cov   = pwm_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // TODO(you): connect agent.ap to sb.ap_imp and to cov's analysis_export.
    // One analysis port can fan out to many subscribers — that is the whole
    // point of TLM. See tutorials/T6.
  endfunction

endclass
```

### Gate A6 — the important one

1. Run the random test. It should pass.
2. **Break the golden model on purpose.** Change `duty - threshold - 1` to
   `duty - threshold - 2` in `dut_pkg`. Re-run.
3. Confirm you get a wall of `UVM_ERROR`, and that the message tells you the duty, the
   expected value and the observed value.
4. Put it back.

**An assertion or scoreboard you have never seen fail is not evidence of anything.** This
20-minute exercise is the difference between a testbench and a testbench you can defend.
Do it at every phase.

Commit.

---

## Step A7 — Functional coverage

### `tb/env/pwm_coverage.sv`

```systemverilog
class pwm_coverage extends uvm_subscriber #(pwm_obs);

  `uvm_component_utils(pwm_coverage)

  int unsigned bits;
  int unsigned threshold;
  pwm_obs      obs;

  covergroup cg_pwm_duty;
    option.per_instance = 1;

    cp_duty: coverpoint obs.duty {
      bins zero          = {0};
      bins one           = {1};
      // TODO(you): the rest, from 03_verification_plan.md §4 —
      //   deadband edge (THRESHOLD, THRESHOLD+1, THRESHOLD+2),
      //   low / mid / high bands, max-1, max.
      //
      // Note: bin expressions must be elaboration-time constants, so you cannot
      // write `bins thr = {threshold}` with a runtime variable. Options:
      //   - hardcode 14 with a comment tying it to the parameter, or
      //   - make the covergroup a `covergroup ... with function sample(int duty)`
      //     and pass computed values in, or
      //   - parameterize the coverage class.
      // Work out which you want; this is a genuine SystemVerilog constraint,
      // not a limitation of your approach.
    }

    cp_saturated: coverpoint (obs.high_cycles == 0) {
      bins output_off = {1};
      bins output_on  = {0};
    }
    // TODO(you): add the other saturation end. Since the R-PWM-4 change,
    // high_cycles == 2**bits (a permanently high output) is reachable at
    // duty = max — it was not reachable upstream. A bin that only fills at
    // full scale proves you actually exercised it.
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_pwm_duty = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO(you): get BITS and THRESHOLD
  endfunction

  // uvm_subscriber declares `write` as pure virtual — you must implement it.
  function void write(pwm_obs t);
    obs = t;
    cg_pwm_duty.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("duty coverage = %.2f%%", cg_pwm_duty.get_coverage()), UVM_LOW)
  endfunction

endclass
```

### Gate A7

Run `pwm_smoke_test` and `pwm_random_test`, and note the coverage each reports. The smoke
test should be low; the random test higher but **not 100%** — the corner bins need
`pwm_corner_test`. Seeing that gap is the point of the exercise: it is the concrete
demonstration of why random alone does not close coverage.

---

## Step A8 — Assertions

Assertions check *every cycle*, not just at transaction boundaries. They catch things a
transaction-level scoreboard structurally cannot, and they cost almost nothing to run.

### `tb/common/sva/pwm_n_bit_sva.sv`

```systemverilog
// Bound into pwm_n_bit — see bind_all.sv. The RTL is never edited.
// Note this module receives Q, an internal DUT signal. `bind` can see internals,
// which is exactly what makes it useful for white-box checking.
module pwm_n_bit_sva #(parameter int BITS = 8, parameter int THRESHOLD = 0) (
  input logic            clk,
  input logic            reset,
  input logic [BITS-1:0] duty,
  input logic [BITS-1:0] Q,
  input logic            pwm_out
);

  default clocking @(posedge clk); endclocking
  default disable iff (reset);

  // R-PWM-2 : the instantaneous output relation, every single cycle.
  // TODO(you): assert that pwm_out equals ((duty > THRESHOLD) && (Q <= duty)).
  //   Do NOT copy the RTL's third term, `&& duty`. It is redundant there (for
  //   THRESHOLD >= 0, duty > THRESHOLD already implies duty >= 1), and an
  //   assertion that transcribes redundant RTL checks nothing extra while
  //   hiding the property you actually mean.
  //
  //   This looks like restating the RTL — and at block level, partly it is.
  //   Its value is that it survives a refactor: rewrite pwm_n_bit as a
  //   pipelined design and this assertion instantly tells you if the
  //   externally visible behaviour changed.
  // a_out_relation: assert property ( ... );

  // R-PWM-1 : the counter increments by one every cycle and wraps cleanly.
  // TODO(you): use $past(Q) or the |=> operator.
  // a_counter_inc: assert property ( ... );

  // R-PWM-5 : reset forces the counter to zero on the next edge.
  //   Note this one deliberately overrides the default disable — you cannot
  //   check reset behaviour with `disable iff (reset)` active.
  a_reset_clears: assert property (
    @(posedge clk) reset |=> (Q == 0)
  );

  // R-PWM-6 : parameter legality. Not a temporal property — just a check at
  // time zero. Cheap insurance against O-PWM-4.
  initial begin
    assert (THRESHOLD >= 0 && THRESHOLD < 2**BITS)
      else $fatal(1, "pwm_n_bit: THRESHOLD=%0d illegal for BITS=%0d", THRESHOLD, BITS);
  end

endmodule
```

### `tb/common/sva/bind_all.sv`

```systemverilog
// One bind per DUT module type. Every instance of pwm_n_bit anywhere in the
// design gets the checker attached — including the one buried inside
// prop_ctrl_pwm at Phase D. That is free reuse: write it once, it protects
// every level.
bind pwm_n_bit pwm_n_bit_sva #(
  .BITS      (BITS),
  .THRESHOLD (THRESHOLD)
) u_pwm_sva (
  .clk     (clk),
  .reset   (reset),
  .duty    (duty),
  .Q       (Q),
  .pwm_out (pwm_out)
);
```

Note the bound module inherits the target instance's parameters by name. That is why the
same bind statement works at `BITS = 8` in Phase A and `BITS = 12` in Phase D with no
changes.

### Gate A8

1. Run — assertions pass.
2. Copy `rtl/pwm_n_bit.sv` to `rtl/pwm_n_bit_broken.sv`, change `Q <= duty` back to
   `Q < duty`, point the filelist at the broken copy, and re-run.

   That mutation is not arbitrary — it is the **upstream expression**, so this is a live
   regression test for "somebody re-synced `rtl/` from `research_2026` and silently undid
   the R-PWM-4 fix." A mutant that models a plausible accident is worth more than one that
   models a typo.
3. Confirm the assertion fires **and** the scoreboard fires. Two independent mechanisms
   catching the same bug is exactly what you want.
4. Revert the filelist. Keep the broken copy in `rtl/mutants/` — Phase E can use it to
   demonstrate that the environment detects seeded faults.

---

## Step A9 — The test suite

Five tests, all thin subclasses of `pwm_base_test` that differ only in which sequence they
start and how it is configured.

| Test | What it does |
|---|---|
| `pwm_smoke_test` | Three fixed duties. Should run in under a second. |
| `pwm_random_test` | 50 random items. The workhorse. |
| `pwm_corner_test` | The directed corner list from `pwm_corner_seq`. |
| `pwm_duty_change_test` | Changes `duty` mid-period. **No scoreboard claim** — the monitor's whole-period model does not apply. Observe, record what happens in `docs/results.md` (O-PWM-5), and move on. |
| `pwm_reset_test` | Asserts reset at random offsets within a period; checks the counter zeroes and the output goes low. |

```systemverilog
class pwm_random_test extends pwm_base_test;
  `uvm_component_utils(pwm_random_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task run_phase(uvm_phase phase);
    pwm_base_seq seq;
    phase.raise_objection(this);
    seq = pwm_base_seq::type_id::create("seq");
    seq.n_items = 50;
    seq.start(env.agent.sequencer);
    // TODO(you): drain — wait long enough for the monitor to publish the last
    //            observation before the objection drops. A few periods is plenty.
    //            Get this wrong and you silently lose the final check.
    phase.drop_objection(this);
  endtask
endclass
```

`pwm_duty_change_test` deserves a note. It is a test whose *purpose is observation*, not
checking. Not every test needs a pass/fail scoreboard; some exist to characterize behaviour
you then write down. Knowing the difference — and saying so in the test's header comment —
is a mark of someone who has actually done this.

---

## Phase A gate

- [ ] All five tests pass across ten seeds each.
- [ ] Duty covergroup ≥ 90% with `pwm_random_test` + `pwm_corner_test` combined.
- [ ] Scoreboard observed failing against a deliberately broken golden model.
- [ ] Assertion observed failing against `pwm_n_bit_broken.sv`.
- [ ] `docs/results.md` has entries for O-PWM-1 through O-PWM-5.
- [ ] Committed.

### Explain these out loud before moving on

If you cannot, re-read the tutorial in brackets — Phase C will be painful otherwise.

1. What does the **sequencer** do that the **sequence** does not? [T6]
2. Why does the driver assign through `vif.drv_cb.duty` rather than `vif.duty`? [T1]
3. What would happen if you removed `phase.raise_objection(this)`? [T3]
4. Why is `pwm_obs` a different class from `pwm_item`?
5. What does `pwm_driver::type_id::create("driver", this)` give you that
   `new("driver", this)` does not? [T5]
6. How does the scoreboard's `write()` method get called? Nothing in your code calls it. [T6]
7. Why is the interface unparameterized?
8. Why does `bind` beat adding assertions directly to `pwm_n_bit.sv`? [T8]
