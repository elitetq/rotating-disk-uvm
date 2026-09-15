# T9 — Functional Coverage

**Read before Phase A step A7.** Coverage answers "did my random stimulus actually reach the
interesting cases?" Without it, random testing is a claim, not a measurement.

---

## Code coverage vs functional coverage

**Code coverage** is automatic: did every line, branch and toggle get exercised? It tells you
what you *missed*. It cannot tell you whether what you exercised was meaningful — 100% line
coverage is achievable with zero checking.

**Functional coverage** is something you write: did the specific scenarios I care about
occur? It measures your *intent*.

You want both, and functional coverage is the one that requires thought.

---

## Covergroups

```systemverilog
class pwm_coverage extends uvm_subscriber #(pwm_obs);
  pwm_obs obs;

  covergroup cg_duty;
    option.per_instance = 1;

    cp_duty: coverpoint obs.duty {
      bins zero     = {0};
      bins one      = {1};
      bins deadband = {[2:14]};      // duty <= THRESHOLD -> output flat low
      bins low      = {[15:63]};      // 15 is the first duty that produces a pulse
      bins mid      = {[64:191]};
      bins high     = {[192:254]};
      bins max      = {255};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_duty = new();          // covergroups must be constructed explicitly
  endfunction

  function void write(pwm_obs t);
    obs = t;
    cg_duty.sample();         // and sampled explicitly
  endfunction
endclass
```

Two things people forget: **construct** the covergroup in `new()`, and **sample** it. A
covergroup that is never sampled reports 0% and looks like a stimulus problem.

`option.per_instance = 1` reports each instance separately rather than merging — you want
this whenever there could be two of something.

---

## Bin forms

```systemverilog
  bins single    = {5};
  bins range     = {[10:20]};
  bins list      = {1, 2, 4, 8};
  bins auto[8]   = {[0:255]};        // 8 equal automatic bins
  bins each[]    = {[0:7]};          // one bin per value

  illegal_bins bad = {[256:511]};    // an ERROR if it ever happens
  ignore_bins  na  = {[100:200]};    // excluded from the total
```

`illegal_bins` is underused. If a value should be impossible, saying so in the covergroup
gets you a free check.

---

## Transition bins

For state machines, *which edges* you traversed matters more than which states you visited:

```systemverilog
  cp_state: coverpoint {a_sync, b_sync} {
    bins s00 = {2'b00};
    bins s10 = {2'b10};

    bins t_00_10 = (2'b00 => 2'b10);
    bins t_10_11 = (2'b10 => 2'b11);
    bins t_long  = (2'b00 => 2'b10 => 2'b11 => 2'b01);   // multi-step
  }
```

Phase C uses these heavily. Visiting all four quadrature states proves almost nothing;
traversing all twelve legal transitions proves you exercised the decoder.

---

## Crosses

```systemverilog
  cp_sign: coverpoint sign_of(value)  { bins neg = {NEG}; bins zero = {ZERO}; bins pos = {POS}; }
  cp_band: coverpoint band_of(value)  { bins small = {SMALL}; bins large = {LARGE}; }

  x_sign_band: cross cp_sign, cp_band {
    // 3 x 2 = 6 bins, minus the impossible ones
    ignore_bins no_negative_zero = binsof(cp_sign) intersect {ZERO} &&
                                   binsof(cp_band) intersect {LARGE};
  }
```

Crosses are where coverage gets expensive fast: three coverpoints of ten bins each is a
thousand cross bins, most meaningless. **Cross deliberately, not reflexively.** Ask what
combination you actually care about.

---

## Sampling: when?

```systemverilog
  covergroup cg @(posedge clk);          // automatic, every clock
  covergroup cg;                          // manual — you call cg.sample()
```

Manual, called from a monitor's `write()`, is usually right: you sample once per *transaction*
rather than once per clock, so a value held for 500 cycles counts once instead of 500 times.
Otherwise a slow test looks like thorough coverage.

---

## Closure

```systemverilog
  option.at_least = 1;      // hits needed before a bin counts as covered
  option.goal     = 100;    // percentage considered "covered"
```

`at_least = 1` is the default and usually right. Raising it to 10 for a bin you want
genuinely exercised — rather than clipped once by luck — is occasionally worth it.

For every unfilled bin at the end, exactly one of:

1. **Add stimulus.** Most holes are this.
2. **Argue unreachable** and `ignore_bins` it *with a comment giving the argument*.
3. **Accept and document**, with a reason someone else can evaluate.

`ignore_bins` without a comment is indistinguishable from hiding a hole, and reviewers treat
it that way. See `08_regression_coverage.md` §E3 for worked examples.

---

## Reading coverage in code

```systemverilog
  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("cg_duty = %.2f%%", cg_duty.get_coverage()), UVM_LOW)
  endfunction
```

`get_coverage()` is the type-level number; `get_inst_coverage()` is this instance's. Printing
them is also your fallback if XSim's merge flow gives you trouble.

---

## Micro-exercise (25 minutes)

1. Add the duty covergroup to your Phase A environment.
2. Run `pwm_smoke_test`. Note the percentage — it will be low.
3. Run `pwm_random_test` with 50 items. Higher, but **not** 100% — the corner bins are too
   narrow for uniform random.
4. Run `pwm_corner_test`. Now they fill.
5. Add `illegal_bins over_max = {[256:511]};` and confirm it never fires.

Step 3 is the point: seeing random stimulus leave a documented, specific hole is the concrete
demonstration of why coverage exists.

---

## Further reading

- IEEE 1800-2017 §19 (functional coverage)
- ChipVerify — SystemVerilog Functional Coverage
- Verification Academy — Coverage Cookbook (the best free treatment of coverage *strategy*,
  as opposed to syntax)
