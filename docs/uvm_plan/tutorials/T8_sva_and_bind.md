# T8 — SystemVerilog Assertions and `bind`

**Read before Phase A.** Assertions check every cycle; scoreboards check every transaction.
You want both, and they catch different things.

---

## Immediate vs concurrent

```systemverilog
  // Immediate — procedural, checked when execution reaches it.
  always_comb assert (state != ILLEGAL) else $error("bad state");

  // Concurrent — temporal, evaluated on a clock across cycles.
  assert property (@(posedge clk) req |=> gnt);
```

Concurrent assertions are the interesting ones: they express relationships **over time**.

---

## Anatomy

```systemverilog
  property p_pulse_single;
    @(posedge clk) disable iff (reset)
      pulse |=> !pulse;
  endproperty

  a_pulse_single: assert property (p_pulse_single)
    else `uvm_error("SVA", "pulse was high two cycles in a row")
```

| Part | Meaning |
|---|---|
| `@(posedge clk)` | sampling clock |
| `disable iff (reset)` | abort evaluation while reset is active |
| `pulse` | antecedent — when this is true... |
| `\|=>` | ...then on the **next** cycle... |
| `!pulse` | ...the consequent must hold |
| label | shows up in the failure message. Always name your assertions. |

**`|->` vs `|=>`:** overlapping (same cycle) vs non-overlapping (next cycle). `|=>` is
exactly `|-> ##1`.

---

## The operators you will actually use

```systemverilog
  a |-> b                  // same cycle
  a |=> b                  // next cycle
  a |-> ##3 b              // exactly 3 cycles later
  a |-> ##[1:5] b          // between 1 and 5 cycles later
  $rose(sig)               // 0 -> 1 this cycle
  $fell(sig)               // 1 -> 0
  $stable(sig)             // unchanged since last cycle
  $past(sig)               // its value one cycle ago
  $past(sig, 3)            // three cycles ago
  $onehot(vec)             // exactly one bit set
  $countones(vec)
```

`$past` is the workhorse for datapath checks:

```systemverilog
  // count changed by exactly the direction indicated when the pulse fired
  a_count_delta: assert property (
    @(posedge clk) disable iff (reset)
      pulse |=> (count == $past(count) + ($past(dir) ? 1 : -1))
  );
```

Note `$past(dir)` inside the consequent: `dir` must be sampled in the antecedent's cycle, not
the consequent's. Getting that alignment right is most of the value of writing the assertion.

---

## `disable iff` — not optional

Without it, every in-flight property fails the moment reset asserts mid-sequence. You get a
screen of errors that mean nothing. A file-wide default:

```systemverilog
  default clocking @(posedge clk); endclocking
  default disable iff (reset);
```

Then individual properties need neither. Except the ones that *check* reset behaviour, which
must override it:

```systemverilog
  a_reset_clears: assert property (@(posedge clk) reset |=> Q == 0);
```

### The `x` problem

If a signal is `x`, comparisons are neither true nor false, and assertions behave in ways
that surprise you. Your `synchronizer` has no reset (O-QUAD-4), so `a_sync`/`b_sync` are `x`
for the first clocks. Gate on a settle flag:

```systemverilog
  logic settled;
  always_ff @(posedge clk, posedge reset)
    if (reset) settled <= 1'b0;
    else       settled <= 1'b1;

  default disable iff (reset || !settled);
```

---

## `bind` — the reason assertions do not touch your RTL

```systemverilog
// In a separate file, compiled with the testbench:
bind pwm_n_bit pwm_n_bit_sva #(
  .BITS(BITS), .THRESHOLD(THRESHOLD)
) u_sva (
  .clk(clk), .reset(reset), .duty(duty), .Q(Q), .pwm_out(pwm_out)
);
```

This instantiates `pwm_n_bit_sva` **inside every instance of `pwm_n_bit`**, anywhere in the
design, without editing `pwm_n_bit.sv`.

Four things that buys you:

1. **The RTL you verify is exactly the RTL you synthesize.** No `` `ifdef SIMULATION ``
   blocks, no risk that the checked version differs from the shipped one.
2. **Internal visibility.** The bound module can connect to `Q`, which is not a port. This is
   how you check a design's internals without exposing them.
3. **Automatic reuse across hierarchy.** One bind statement covers the `pwm_n_bit` inside
   `prop_ctrl_pwm` at Phase D. Write once, protects every level.
4. **Parameter inheritance.** `.BITS(BITS)` picks up each target instance's own parameter, so
   the same bind works at `BITS = 8` and `BITS = 12`.

You can also bind to a specific instance:

```systemverilog
bind tb_ctrl_top.DUT.PWM pwm_n_bit_sva #(...) u_sva (...);
```

---

## Assertions that check the testbench

Perfectly legitimate, and this project uses one:

```systemverilog
  // A quadrature encoder cannot change both channels in one clock.
  // If this fires, MY DRIVER is generating illegal stimulus.
  a_single_channel: assert property (
    @(posedge clk) disable iff (reset)
      !($changed(ch_a) && $changed(ch_b))
  );
```

Without it, an illegal-stimulus bug presents as a DUT bug, and you can lose a day to it.

---

## Coverage from assertions

```systemverilog
  c_saturated: cover property (@(posedge clk) pwm_cmp == (2**BITS - 1));
```

`cover property` records how often a sequence occurred. Complements covergroups: covergroups
sample values, cover properties sample *temporal behaviour*. "Did a direction reversal ever
occur within two cycles of a saturation event?" is a cover property, not a covergroup.

---

## Micro-exercise (30 minutes)

Write `pwm_n_bit_sva` with the output-relation property, bind it, and run:

1. Confirm it passes on correct RTL.
2. Copy the RTL, change `Q <= duty` to `Q < duty`, point the filelist at the copy, re-run.
   Confirm the assertion fires and read the message. (That mutation reverts
   `rtl/pwm_n_bit.sv` to the upstream expression — see `rtl/PROVENANCE.md` §2 — so it is a
   realistic accident, not an invented one.)
3. Remove `disable iff (reset)` and run a test that asserts reset mid-stream. Observe the
   noise.
4. Add `cover property` on `duty == 0` and check the coverage report shows the hit count.

Step 2 is mandatory before you trust any assertion. **An assertion you have never seen fail
is not evidence of anything.**

---

## Further reading

- IEEE 1800-2017 §16 (assertions), §23.11 (`bind`)
- Cerny, Dudani, Havlicek, Korchemny — *SVA: The Power of Assertions in SystemVerilog*
- Verification Academy — SVA cookbook (the best free resource on this)
- ChipVerify — SystemVerilog Assertions
