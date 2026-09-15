# T1 — Interfaces, Modports, and Clocking Blocks

**Read before Phase A.** The single most common testbench bug in the industry lives here.

---

## The problem interfaces solve

Without one, connecting a testbench to a DUT means declaring every signal separately and
repeating the port list everywhere:

```systemverilog
logic clk, reset, pwm_out;
logic [7:0] duty;
pwm_n_bit DUT (.clk(clk), .reset(reset), .duty(duty), .pwm_out(pwm_out));
```

Add a signal and you edit four places. An `interface` bundles them into one named thing:

```systemverilog
interface pwm_if (input logic clk);
  logic       reset;
  logic [7:0] duty;
  logic       pwm_out;
endinterface
```

```systemverilog
pwm_if vif (.clk(clk));
pwm_n_bit DUT (.clk(clk), .reset(vif.reset), .duty(vif.duty), .pwm_out(vif.pwm_out));
```

Convenient. But the reason UVM *needs* interfaces is different: **classes cannot reference
the module hierarchy.** A class is a dynamic object with no fixed place in the design tree.
A `virtual interface` is a handle to a static interface instance, and that handle can be
stored in a class field and passed around.

```systemverilog
class pwm_driver extends uvm_driver #(pwm_item);
  virtual pwm_if vif;      // a handle, set at run time via config_db
endclass
```

That is the whole reason interfaces are mandatory in UVM.

---

## Modports: who drives what

```systemverilog
  modport DRV (output reset, duty, input pwm_out);
  modport MON (input reset, duty, pwm_out);
```

A modport restricts direction from a particular point of view. The compiler will now reject a
monitor that tries to drive `duty` — which is worth having, because a monitor that
accidentally drives is a bug that produces beautifully consistent, entirely wrong results.

---

## Clocking blocks: the part that matters

### The race

Two processes, both sensitive to the same edge:

```systemverilog
// driver
always @(posedge clk) vif.duty = item.duty;

// monitor
always @(posedge clk) obs.duty = vif.duty;
```

**Which value does the monitor read — this item's or the previous one's?**

The language does not say. Both processes are triggered by the same event; the scheduler may
run either first. The answer can change between simulators, between versions, between
optimization levels, and when you add a `$display`.

Symptoms:
- The scoreboard is consistently one transaction behind.
- A test passes with `WAVES=0` and fails with `WAVES=1`.
- Adding a debug print "fixes" it.

You will reproduce this deliberately in Phase B, step B1. Doing so once is worth more than
reading this three times.

### The fix

```systemverilog
  clocking drv_cb @(posedge clk);
    default input #1step output #1ns;
    output reset, duty;
    input  pwm_out;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input reset, duty, pwm_out;
  endclocking
```

- **`input #1step`** — sample in the *preponed* region, before anything in this timestep
  changes. This is the same instant the DUT's own flops sample, so the monitor sees exactly
  what the hardware saw. `1step` is a simulation region, not a time unit.
- **`output #1ns`** — the driver's value lands 1 ns *after* the edge, so the DUT can never
  see it in the same cycle it was driven.

Now the ordering is fixed by the language rather than by luck.

### Using them

```systemverilog
  vif.drv_cb.duty <= item.duty;     // drive: nonblocking, through the clocking block
  repeat (10) @(vif.drv_cb);        // advance 10 clocks

  obs.duty = vif.mon_cb.duty;       // sample
  @(vif.mon_cb);                    // advance one clock
```

**Rule: once an interface has a clocking block, never touch the raw signals from a class.**
`vif.duty <= x` bypasses the skew and reintroduces the race, and it looks identical to the
correct code at a glance.

---

## The SystemVerilog scheduler, briefly

Each timestep has ordered regions. The three that matter:

| Region | What happens |
|---|---|
| **Preponed** | Clocking-block inputs sampled. Nothing has changed yet this timestep. |
| **Active** | Blocking assignments, `always_comb`, process execution. Order *within* is undefined. |
| **NBA** | Nonblocking assignment updates land — this is when flops actually change. |

Clocking blocks work by pinning your sampling to Preponed and your driving to after NBA. The
race exists because two Active-region processes have no defined order.

---

## Micro-exercise (20 minutes)

```systemverilog
module race_demo;
  logic clk = 0, sig = 0;
  always #5 clk = ~clk;

  initial begin
    repeat (10) begin
      @(posedge clk);
      sig = ~sig;              // process A: drives at the edge
    end
    $finish;
  end

  always @(posedge clk)
    $display("%0t  B sees sig = %b", $time, sig);   // process B: samples at the edge

  initial $display("Which value does B print each cycle? Predict, then run.");
endmodule
```

Run it. Then swap `sig = ~sig` for `sig <= ~sig` and run again. Then add a clocking block and
sample through it. Three runs, three behaviours, one lesson.

---

## Further reading

- IEEE 1800-2017 §25 (interfaces), §14 (clocking blocks), §4 (scheduling)
- ChipVerify — SystemVerilog Interface / Clocking Block
- Verification Academy — "SystemVerilog Interfaces" and the race-condition sessions
- Cummings, *SystemVerilog Event Regions, Race Avoidance & Guidelines* (SNUG). The definitive
  treatment; dense, but every UVM engineer has read it.
