# T7 — Constrained Randomization

**Read before Phase B.** The difference between "random tests" and useful stimulus.

---

## The core idea

```systemverilog
class packet;
  rand bit [7:0]  addr;
  rand bit [15:0] len;

  constraint c_len   { len inside {[1:512]}; }
  constraint c_align { addr % 4 == 0; }
endclass

packet p = new();
if (!p.randomize()) $error("unsatisfiable");
```

`randomize()` runs a constraint solver over every `rand` field and every active constraint,
returning a random solution — or **0** if no solution exists.

**Always check the return value.** `void'(p.randomize())` silently leaves stale values in
the object when constraints conflict, and the test proceeds with whatever was there before.

---

## `rand` vs `randc`

- `rand` — independent each call. Values can repeat.
- `randc` — cyclic: every value in the range appears once before any repeats.

`randc` is only legal on types up to 16 bits (the solver has to hold the permutation), and is
useful for sweeping a small enumerated space exhaustively in random order — a state enum, a
mode select.

---

## Constraint forms

```systemverilog
  constraint c1 { len inside {[1:512]}; }              // range
  constraint c2 { mode inside {READ, WRITE}; }         // set
  constraint c3 { !(addr inside {[0:15]}); }           // negated set
  constraint c4 { len > 0 -> data.size() == len; }     // implication
  constraint c5 { if (mode == READ) len == 1;
                  else             len inside {[1:8]}; }
  constraint c6 { foreach (data[i]) data[i] < 256; }   // over an array
  constraint c7 { solve mode before len; }             // solve order
```

`solve ... before` does not change which solutions are *legal* — it changes their
*distribution*. Without it the solver picks uniformly across the whole solution space, which
can make one variable's values heavily skewed by how many partners each has.

---

## `dist` — the one that matters most for this project

```systemverilog
  constraint c_dist {
    value dist {
      0              := 10,        // weight 10 to the single value 0
      [1:99]         := 10,        // weight 10 to EACH of 1..99  → 990 total
      [100:1000]     :/ 10         // weight 10 SPLIT across 100..1000
    };
  }
```

| Operator | Meaning |
|---|---|
| `:=` | this weight applies to **each value** in the range |
| `:/` | this weight is **divided across** the range |

Getting these backwards is the classic mistake: `[0:2**31] := 1` gives a wide range
overwhelming weight and your corner cases never appear.

### Why this matters here

Phase B's `magnitude_clamp` takes a 32-bit value. The interesting values are `0`, `±1`,
`±CLAMP_VAL`, `±(CLAMP_VAL+1)`, `INT_MAX`, `INT_MIN` — nine out of 4 294 967 296.

At one item per microsecond of simulated time, uniform random would take on the order of
**136 000 years** to hit all nine.

Uniform random is not good random. `dist` is how you fix that.

---

## Inline constraints

```systemverilog
  if (!item.randomize() with { duty inside {[0:max_duty]};
                               hold_periods == 1; })
    `uvm_error("RAND", "failed")
```

Applied on top of the class's constraints, for this call only. Useful when a sequence knows
something the item cannot.

**In-class vs inline:** in-class keeps the knowledge with the data and scales better; inline
keeps the item dumb and reusable. Both are defensible — pick per case and be able to say why.

---

## Turning things off

```systemverilog
  item.duty.rand_mode(0);          // this field stops being randomized
  item.c_range.constraint_mode(0); // this constraint stops applying
```

Useful for a directed test reusing a random item class. Overused, it makes stimulus
unpredictable — prefer a subclass with different constraints.

---

## `pre_randomize` / `post_randomize`

```systemverilog
  function void post_randomize();
    checksum = compute_checksum(data);    // derived, not solved
  endfunction
```

Put values the solver does not need to reason about here. Putting a checksum in a constraint
makes the solver do algebra it should not have to.

---

## Debugging an unsatisfiable constraint

`randomize()` returns 0. Now what?

1. **Disable constraints one at a time** with `constraint_mode(0)` until it succeeds. The
   last one you disabled conflicts.
2. **Print the state** — a non-`rand` field feeding a constraint may have an impossible value
   (`max_duty` still 0 because the sequence forgot to set it).
3. **Watch for over-constraint across inheritance.** A subclass's constraint *adds* to the
   parent's; it does not replace it. Two ranges that do not intersect give you nothing.
4. Some simulators report the conflicting constraint set. XSim's diagnostics are thin here —
   method 1 is usually faster than reading the message.

---

## Seeds

```bash
make PHASE=pwm TEST=pwm_random_test SEED=42 run
```

`-sv_seed 42` makes the run bit-identical every time. **Always record the seed.** A failure
you cannot reproduce is a failure you cannot fix, and "it failed once last week" is not a bug
report.

If two runs with the same seed differ, something is drawing randomness outside the seeded
stream — usually `$random` (which uses a separate, differently-seeded generator). Use
`randomize()` and `$urandom` only.

---

## Micro-exercise (30 minutes)

```systemverilog
class demo;
  rand bit signed [31:0] value;
  int clamp_val = 255;
  constraint c_uniform { }      // start empty
endclass
```

1. Randomize 1000 times with no constraint. Histogram how many landed in
   `{0, ±1, ±255, ±256}`. (Answer: essentially zero.)
2. Add a `dist` constraint weighting those corners. Re-run. Count again.
3. Deliberately swap a `:=` for a `:/` on a wide range and watch the corner hits collapse.

Twenty minutes, and `:=` versus `:/` becomes permanent.

---

## Further reading

- IEEE 1800-2017 §18 (constrained random)
- ChipVerify — SystemVerilog Constraints (excellent worked examples)
- Spear & Tumbush, *SystemVerilog for Verification*, ch. 6
- Verification Academy — Randomization cookbook
