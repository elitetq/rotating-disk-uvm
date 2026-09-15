# Phase B — `magnitude_clamp`

**Goal:** learn constrained randomization properly, and see the driver/monitor race with your
own eyes before you learn to prevent it.

**Time:** 3–4 days. **Prerequisite:** Phase A gate passed.

The DUT is combinational and trivial. That is the point — with no timing behaviour to check,
every bit of difficulty moves into **stimulus quality**, which is the actual subject of this
phase.

**Read first:** `tutorials/T7` (randomization), `tutorials/T1` (clocking blocks) again.

---

## The DUT

```systemverilog
module magnitude_clamp #(parameter int CLAMP_VAL) (
    input  logic signed [31:0]             value,
    output logic [$clog2(CLAMP_VAL+1)-1:0] clamped_value,
    output logic                           dir
);
```

Golden model (`02_design_under_test.md` §2):

```
dir           = (value < 0)                 // signed; value == 0 gives dir = 0
clamped_value = min(|value|, CLAMP_VAL)
```

---

## Step B1 — Build it wrong first, on purpose

This is the only step in the guide that asks you to write code you will then throw away.
It is worth the hour.

### `tb/common/clamp_if.sv` — first version, deliberately raceable

```systemverilog
interface clamp_if (input logic clk);

  logic signed [31:0] value;
  logic        [31:0] clamped_value;   // wide; the TB top zero-extends the DUT output
  logic               dir;

  // NO clocking block. The driver will assign directly and the monitor will
  // sample directly, both in the same simulation timestep.
  modport DRV (output value, input clamped_value, dir);
  modport MON (input value, clamped_value, dir);

endinterface
```

Write the driver to assign on the clock edge:

```systemverilog
  task drive(clamp_item item);
    @(posedge vif.clk);
    vif.value = item.value;        // blocking assignment, at the edge
  endtask
```

and the monitor to sample on the same edge:

```systemverilog
  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      obs.value         = vif.value;          // which value? this cycle's or last cycle's?
      obs.clamped_value = vif.clamped_value;
      obs.dir           = vif.dir;
      ap.write(obs);
    end
  endtask
```

### Gate B1 — reproduce the failure

Run `clamp_random_test` across ten seeds. You are looking for one of:

- The scoreboard reports mismatches where the observed output corresponds to the **previous**
  item's input.
- Results differ between runs with the same seed, or between `WAVES=0` and `WAVES=1`.
- It passes, but a single added `$display` anywhere changes the result.

**Write down exactly what you saw.** Then read `tutorials/T1` and make sure you can explain
it: both processes are sensitive to `posedge clk`, SystemVerilog does not define their
relative order within the timestep, and the scheduler is free to run them in either order.
The output you observe therefore depends on scheduling, not on logic.

This is the single most common testbench bug in the industry, it is invisible in a waveform,
and having personally caused it once is worth more than reading about it three times.

---

## Step B2 — Fix it with clocking blocks

```systemverilog
interface clamp_if (input logic clk);

  logic signed [31:0] value;
  logic        [31:0] clamped_value;
  logic               dir;

  clocking drv_cb @(posedge clk);
    default input #1step output #1ns;
    output value;
    input  clamped_value, dir;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input value, clamped_value, dir;
  endclocking

  modport DRV (clocking drv_cb);
  modport MON (clocking mon_cb);

endinterface
```

Driver drives `vif.drv_cb.value <= item.value;`. Monitor samples `vif.mon_cb.value` etc.

Now the ordering is defined by the language, not by luck: the monitor samples in the
preponed region (before anything changes this timestep), and the driver's value lands 1 ns
after the edge.

### One subtlety this DUT exposes

`magnitude_clamp` is **purely combinational**. If the driver applies `value` 1 ns after edge
N, the outputs settle almost immediately, and the monitor sampling in the preponed region of
edge N+1 sees the matching pair. Good.

But convince yourself of that rather than taking it on faith — draw the timeline:

```
   edge N            edge N+1
     |                  |
     |  +1ns            |
     |--> value applied  |
     |    outputs settle |
     |                  |<-- monitor samples value AND outputs here, consistent
```

The monitor sees `value` one cycle *later* than the driver applied it, but it sees the
inputs and outputs from the *same* instant, which is all a combinational check needs.

### Gate B2

Same test, twenty seeds, stable and passing. You can state in one sentence why B1 failed and
B2 does not. Commit both versions if you like — a commit titled "reproduce driver/monitor
race" followed by "fix with clocking blocks" is a good thing to have in a public repo.

---

## Step B3 — The golden model

Add to `tb/common/dut_pkg.sv`:

```systemverilog
  typedef struct packed {
    logic [31:0] magnitude;
    logic        dir;
  } clamp_result_t;

  // ------------------------------------------------------------------
  // magnitude_clamp  (02_design_under_test.md §2)
  //
  //   dir       = value < 0
  //   magnitude = min(|value|, clamp_val)
  //
  // CAREFUL: |INT_MIN| is 2**31, which does NOT fit in a signed 32-bit int.
  // Compute the magnitude in a 64-bit type, then narrow. If you use `int`
  // here your model will be wrong for exactly the corner case the DUT gets
  // right — and you will spend an afternoon blaming the RTL. (O-CLAMP-1)
  // ------------------------------------------------------------------
  function automatic clamp_result_t expected_clamp(input longint signed value,
                                                   input longint        clamp_val);
    // TODO(you): four or five lines.
  endfunction
```

### Gate B3

Call it from a plain `initial` block for
`{0, 1, -1, 100, -100, 101, -101, 32'sh7FFF_FFFF, 32'sh8000_0000}` at `clamp_val = 100` and
check every answer by hand. Pay attention to `32'sh8000_0000`: the expected magnitude is
2 147 483 648, which clamps to 100 with `dir = 1`.

---

## Step B4 — The agent

Copy the Phase A agent and adapt. This should take under an hour, and if it takes longer,
that is a signal your Phase A components had DUT-specific knowledge baked in where it did
not belong. Note what you had to change.

```systemverilog
class clamp_item extends uvm_sequence_item;
  rand bit signed [31:0] value;

  // Not rand — the sequence or test sets it before randomize(), so constraints
  // can refer to the configured CLAMP_VAL.
  int clamp_val = 255;

  `uvm_object_utils_begin(clamp_item)
    `uvm_field_int(value,     UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(clamp_val, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "clamp_item"); super.new(name); endfunction
endclass
```

The `UVM_NOCOMPARE` flag on a configuration field is a small but real detail: it stops the
field from participating in `compare()`, so two items with the same stimulus but different
config still count as equal. You will not need `compare()` here, but the habit is right.

### Gate B4

`clamp_random_test` passes at `CLAMP_VAL = 255` across twenty seeds.

---

## Step B5 — Constraints, the actual subject of this phase

### The problem, stated concretely

`value` is 32 bits. Uniform random gives each of 2³² values equal probability. The corner
cases you care about are:

```
0, +1, -1, +CLAMP_VAL, -CLAMP_VAL, +(CLAMP_VAL+1), -(CLAMP_VAL+1),
32'h7FFF_FFFF, 32'h8000_0000
```

Nine values out of 4 294 967 296. At one item per microsecond of simulation you would expect
to hit all nine after roughly **136 000 years of continuous simulation**.

Uniform random is not the same as good random. This is the whole lesson.

### The fix

```systemverilog
class clamp_corner_item extends clamp_item;
  `uvm_object_utils(clamp_corner_item)
  function new(string name = "clamp_corner_item"); super.new(name); endfunction

  // TODO(you): a dist constraint that weights the interesting values heavily
  // while still sampling the bulk ranges. Sketch:
  //
  //   constraint c_corners {
  //     value dist {
  //       0                       := 10,
  //       1                       := 10,
  //      -1                       := 10,
  //       clamp_val               := 10,
  //      -clamp_val               := 10,
  //       clamp_val + 1           := 10,
  //      -(clamp_val + 1)         := 10,
  //       32'sh7FFF_FFFF          :=  5,
  //       32'sh8000_0000          :=  5,
  //       [1 : clamp_val-1]       :/ 15,
  //       [-(clamp_val-1) : -1]   :/ 15,
  //       [clamp_val+2 : 1000000] :/ 10,
  //       ...
  //     };
  //   }
  //
  // Two operators, and the difference matters:
  //   :=  gives EACH value in the range that weight
  //   :/  splits the weight ACROSS the whole range
  // Get them backwards and a wide range swamps everything else.
  // See tutorials/T7.
endclass
```

### The constraint-solver trap to watch for

`clamp_val` is a non-`rand` field, so the solver treats it as a constant — fine. But if you
ever make a configuration field `rand`, the solver will happily pick a `clamp_val` that makes
your other constraints unsatisfiable, and `randomize()` starts returning 0. Two habits that
prevent a lot of confusion:

- Always check the return value: `if (!item.randomize()) uvm_error(...)`. Never
  `void'(item.randomize())` in production code.
- Keep configuration non-`rand` unless you specifically want it randomized.

### Gate B5

`clamp_corner_test` hits every corner bin in the covergroup within 200 items. If a bin never
fills, your `dist` weights are wrong — print the values and look at the histogram before
guessing.

---

## Step B6 — Parameterization

Run the identical agent, environment and tests at `CLAMP_VAL` = 100, 255, 4095, with **no
source changes**.

This is where the "unparameterized interface" decision from Phase A pays off. The interface
is 32 bits wide regardless; only the DUT instance and a `config_db` integer change.

### Approach: parameterize the TB top, override at elaboration

```systemverilog
module tb_clamp_top #(parameter int CLAMP_VAL = 255);

  localparam int W = $clog2(CLAMP_VAL + 1);

  logic clk = 0;
  always #5ns clk = ~clk;

  clamp_if vif (.clk(clk));

  logic [W-1:0] dut_clamped;

  magnitude_clamp #(.CLAMP_VAL(CLAMP_VAL)) DUT (
    .value         (vif.value),
    .clamped_value (dut_clamped),
    .dir           (vif.dir)
  );

  assign vif.clamped_value = 32'(dut_clamped);   // widen into the fixed-width interface

  initial begin
    uvm_config_db#(virtual clamp_if)::set(null, "*", "vif", vif);
    uvm_config_db#(int)::set(null, "*", "CLAMP_VAL", CLAMP_VAL);
    run_test();
  end

endmodule
```

Override at elaboration:

```bash
xelab -L uvm --relax -timescale 1ns/1ps -s clamp_snap \
      -generic_top "CLAMP_VAL=4095" tb_clamp_top
```

Add a `PARAM` knob to the Makefile:

```makefile
PARAM ?=
ifneq ($(PARAM),)
  XELAB_FLAGS += -generic_top "$(PARAM)"
endif
```

```bash
make PHASE=clamp TEST=clamp_random_test PARAM="CLAMP_VAL=4095" run
```

> `-generic_top` sets parameters on the **elaboration top** only, not on arbitrary instances
> deeper in the hierarchy. That is enough here because the TB top passes the value down. If
> you ever need to override a parameter mid-hierarchy, the answer is a `defparam`-free
> restructure — plumb it from the top, as here.

### Gate B6

All three configurations pass ten seeds each. Add the three runs to `regress.py`'s test list
so the regression covers them permanently.

---

## Step B7 — Assertions and coverage

### `tb/common/sva/magnitude_clamp_sva.sv`

```systemverilog
// Combinational DUT: these are immediate/concurrent checks with no clock
// relationship to worry about, but they still need a sampling clock.
module magnitude_clamp_sva #(parameter int CLAMP_VAL = 255) (
  input logic                             clk,
  input logic signed [31:0]               value,
  input logic [$clog2(CLAMP_VAL+1)-1:0]   clamped_value,
  input logic                             dir
);

  // TODO(you): a_never_exceeds  — clamped_value <= CLAMP_VAL, always.
  //   Note this can never fail given the RTL, because the output is only
  //   $clog2(CLAMP_VAL+1) bits wide... unless CLAMP_VAL is not 2**n - 1,
  //   in which case it CAN. Try CLAMP_VAL=100 (7 bits, holds up to 127).
  //   Worth writing for that reason alone.

  // TODO(you): a_dir_matches_sign — dir == (value < 0). Careful with the
  //   signedness of the comparison; `value` is declared signed here, so
  //   `value < 0` does what you expect, but check it.

  // TODO(you): a_zero_is_positive — value == 0 |-> dir == 0.
  //   A one-line assertion for a one-line requirement (R-CLP-1). It matters
  //   because "is zero positive or negative" is exactly the kind of convention
  //   that gets flipped in a refactor.

  initial begin
    assert (CLAMP_VAL >= 1)
      else $fatal(1, "magnitude_clamp: CLAMP_VAL=%0d illegal (O-CLAMP-3)", CLAMP_VAL);
  end

endmodule
```

Add the bind to `bind_all.sv`.

### Coverage

```systemverilog
covergroup cg_clamp;
  option.per_instance = 1;

  cp_sign: coverpoint sign_of(obs.value) {
    bins negative = {SIGN_NEG};
    bins zero     = {SIGN_ZERO};
    bins positive = {SIGN_POS};
  }

  cp_band: coverpoint band_of(obs.value, clamp_val) {
    bins b_zero      = {BAND_ZERO};
    bins b_one       = {BAND_ONE};
    bins b_below     = {BAND_BELOW};      // 1 < |v| < CLAMP_VAL
    bins b_exact     = {BAND_EXACT};      // |v| == CLAMP_VAL
    bins b_above     = {BAND_ABOVE};      // |v| == CLAMP_VAL + 1
    bins b_far_above = {BAND_FAR};        // |v| >> CLAMP_VAL
    bins b_int_min   = {BAND_INT_MIN};
  }

  // TODO(you): cross cp_sign and cp_band.
  //   Then add ignore_bins for the impossible combinations —
  //   there is no such thing as a negative zero, and BAND_INT_MIN only
  //   exists on the negative side.
  //   Leaving impossible bins in place means you can never reach 100%,
  //   and a covergroup that can never close is a covergroup everyone learns
  //   to ignore.
endgroup
```

`sign_of()` and `band_of()` are helper functions — put them in `dut_pkg` with the enums, not
in the coverage class. They are pure functions about the design, which is what `dut_pkg` is
for, and the scoreboard may want them too.

### Gate B7

Cross coverage at 100% (after `ignore_bins`), all assertions bound and observed firing
against a broken copy of the RTL.

---

## Phase B gate

- [ ] Three tests × three `CLAMP_VAL` configurations × ten seeds, all passing.
- [ ] Cross coverage 100% with documented `ignore_bins`.
- [ ] `docs/results.md` records what the DUT does with `32'h8000_0000` and whether you
      consider it correct (O-CLAMP-1).
- [ ] The B1 race is written up in your notes — one paragraph on what you observed and why.
- [ ] Committed.

### Explain these out loud

1. What is the difference between `:=` and `:/` in a `dist` constraint? [T7]
2. Why does `randomize()` return a value, and what should you do with it? [T7]
3. Your B1 monitor sampled `vif.value` at `posedge clk`. Which value did it get, and why is
   that question not answerable from the source alone? [T1]
4. Why is `clamp_val` a non-`rand` field?
5. Why does the interface carry a 32-bit `clamped_value` when the DUT output is 7 bits at
   `CLAMP_VAL = 100`?
