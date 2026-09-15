# Phase C — `decoder_to_32_bit`

**Goal:** build a driver that speaks a **protocol** instead of writing values, and a monitor
that **reconstructs** transactions from pin activity.

**Time:** 1.5–2 weeks. **Prerequisite:** Phase B gate passed.

This is the phase that makes the project worth showing. Everything before it was plumbing on
DUTs simple enough to check with a formula. Here the stimulus has structure, timing and
sequencing, the DUT has internal state you cannot see, and the checking has to survive both.
That is what block-level verification actually looks like.

**Read first:** `tutorials/T7` (randomization) and `tutorials/T8` (SVA), plus
`02_design_under_test.md` §3 — read that section until you can draw the state diagram from
memory.

---

## Step C1 — Understand the DUT before writing anything

**Do not skip this.** `first_value_priority` is *not* a textbook 4× quadrature decoder.
Assuming it is will cost you two days.

### The quadrature waveform

```
            ┌───────┐       ┌───────┐       ┌───────┐
   ch_a  ───┘       └───────┘       └───────┘       └───   forward rotation
                ┌───────┐       ┌───────┐       ┌───────
   ch_b  ───────┘       └───────┘       └───────┘

state:    00  10  11  01  00  10  11  01  00  10  11  01
          └── one quadrature cycle ──┘
```

Reverse rotation is the same waveform with A and B swapped: `00 → 01 → 11 → 10 → 00`.

### The state diagram, with the DUT's actual counting rules

```
                     ┌──────────────────────────────┐
                     │                              │
        UP pulse     ▼          no pulse            │  no pulse
     ┌────────────  00  ─────────────► 10 ─────────────► 11
     │  (a rose,    ▲ ▲               │                  │
     │   b low)     │ │               │                  │
     │              │ │  DOWN pulse   │  DOWN pulse      │  no pulse
     │              │ └───────────────┘  (a fell,        ▼
     │              │                     b low)         01
     │              │                                    │
     │              │  UP pulse (b fell, a low)          │
     │              └────────────────────────────────────┘
     │
     └──► DOWN pulse (b rose, a low) leads to 01 on the reverse path
```

Written as conditions, straight from the RTL:

| Transition | Condition in the RTL | Pulse | Guard |
|---|---|:--:|---|
| `00 → 10` | `~a_sync[1] && a_sync[0] && ~b_sync[0]` | **UP** | blocked if `up_lock[1]` |
| `01 → 00` | `b_sync[1] && ~b_sync[0] && ~a_sync[0]` | **UP** | blocked if `up_lock[1]` |
| `00 → 01` | `~b_sync[1] && b_sync[0] && ~a_sync[0]` | **DOWN** | blocked if `down_lock[1]` |
| `10 → 00` | `a_sync[1] && ~a_sync[0] && ~b_sync[0]` | **DOWN** | blocked if `down_lock[1]` |
| any other | — | none | — |

And the lock rules:

- An UP pulse sets `up_lock`, clears `down_lock`. A DOWN pulse does the reverse.
- **Both** locks clear only when A and B have been low for **two consecutive samples** —
  the encoder resting at the `00` detent.

### Net result: one count per full quadrature cycle

Trace forward `00 → 10 → 11 → 01 → 00`:

| Step | UP? | DOWN? | Lock | Pulse |
|---|---|---|---|---|
| `00 → 10` | yes | — | `up_lock` clear | **+1** |
| `10 → 11` | no | no | | none |
| `11 → 01` | no | no | | none |
| `01 → 00` | yes | — | `up_lock` **set** | suppressed |
| rest at `00` | — | — | both locks clear | — |

Reverse is exactly symmetric: `00 → 01` fires DOWN, `10 → 00` is suppressed by `down_lock`.

### Latency: four `clk` edges, pin to `count`

```
pin change ──┬─ edge 1: synchronizer stage 1
             ├─ edge 2: synchronizer stage 2  → a_sync[0]/b_sync[0] valid
             ├─ edge 3: first_value_priority  → pulse high for one cycle
             └─ edge 4: directional_counter   → count updated
```

Your monitor needs this exactly. Get it wrong and every check is off by a few cycles.

### Gate C1

Write `tb/top/tb_quad_top.sv` with a temporary `initial` block that walks **one forward
quadrature cycle** by hand, with generous waits between states, and `$display`s `count`
before and after.

`count` must go from 0 to 1, and the pulse must appear four edges after the `ch_a` rise.
Then walk one reverse cycle and confirm `count` returns to 0.

**If this does not match, stop.** Everything else in Phase C assumes you have the model
right.

---

## Step C2 — The interface

```systemverilog
// tb/common/quad_if.sv
interface quad_if (input logic clk);

  logic               reset;
  logic               ch_a, ch_b;

  // Observed outputs
  logic signed [31:0] count;

  // White-box probes, driven by the TB top from inside the DUT hierarchy.
  // See the note below — this is a deliberate choice, not laziness.
  logic               pulse;
  logic               dir;
  logic        [1:0]  a_sync, b_sync;

  clocking drv_cb @(posedge clk);
    default input #1step output #1ns;
    output reset, ch_a, ch_b;
    input  count, pulse, dir;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input reset, ch_a, ch_b, count, pulse, dir, a_sync, b_sync;
  endclocking

  modport DRV (clocking drv_cb);
  modport MON (clocking mon_cb);

endinterface
```

### On white-box probing

`pulse`, `dir`, `a_sync` and `b_sync` are internal to `first_value_priority`. `count` is a
real output of `decoder_to_32_bit`. Bringing the internals out to the interface is a
**deliberate trade-off**, and you should be able to defend it:

**For:** the observable output (`count`) alone is a very weak checking surface. Pulse-level
checking catches a bug in the cycle it happens rather than N steps later. State-transition
coverage is impossible without seeing `a_sync`/`b_sync`.

**Against:** the testbench now depends on internal signal names. Rename `pulse` in the RTL and
the testbench breaks — which is not a false alarm exactly, but it is noise.

**The compromise used here:** the *scoreboard* checks only `count`, which is a genuine output,
so the pass/fail verdict is black-box. The *assertions and coverage* use the probes, because
they are diagnostic and coverage aids rather than the verdict. If the probes disappear you
lose visibility, not correctness.

Wire them in the TB top with hierarchical references:

```systemverilog
  assign vif.pulse  = DUT.AB_DIR.pulse;
  assign vif.dir    = DUT.AB_DIR.dir;
  assign vif.a_sync = DUT.AB_DIR.a_sync;
  assign vif.b_sync = DUT.AB_DIR.b_sync;
```

Write the trade-off into your README. "I probed internals for coverage but kept the verdict
black-box" is a considered position; unexplained hierarchical references look like an
accident.

---

## Step C3 — The sequence item, at the right level of abstraction

Here is where Phase C differs from everything before it. A `pwm_item` was a value. A
`quad_item` is **an instruction to the driver about how to move the disk**.

```systemverilog
typedef enum bit { QUAD_REVERSE = 1'b0, QUAD_FORWARD = 1'b1 } quad_dir_e;

typedef enum bit [1:0] {
  QUAD_S00 = 2'b00,   // {a, b}
  QUAD_S10 = 2'b10,
  QUAD_S11 = 2'b11,
  QUAD_S01 = 2'b01
} quad_state_e;

class quad_item extends uvm_sequence_item;

  rand quad_dir_e   direction;
  rand int unsigned n_steps;             // full quadrature cycles to walk
  rand int unsigned clks_per_state;      // how long to hold each of the 4 states
  rand bit          inject_dither;
  rand quad_state_e dither_state;        // where the dither happens
  rand int unsigned dither_count;        // how many rattles

  `uvm_object_utils_begin(quad_item)
    `uvm_field_enum(quad_dir_e,   direction,     UVM_ALL_ON)
    `uvm_field_int (n_steps,      UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (clks_per_state, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (inject_dither,  UVM_ALL_ON)
    `uvm_field_enum(quad_state_e, dither_state,  UVM_ALL_ON)
    `uvm_field_int (dither_count,   UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "quad_item"); super.new(name); endfunction

  // TODO(you): constraints.
  //
  //   c_steps  : n_steps in [1:200]. Bigger is slower, not better.
  //
  //   c_timing : clks_per_state >= 2.
  //              Why 2? The lock only clears when 00 is observed for two
  //              consecutive SYNCHRONIZED samples (02_design_under_test.md §3,
  //              O-QUAD-1). One clock per state and the decoder silently stops
  //              counting. Default your constraint to the legal range so the
  //              ordinary random test stays in spec — then write a SEPARATE
  //              sequence that deliberately goes below it, because finding that
  //              knee is a result worth having.
  //
  //   c_dither : dither_count in [1:20]; keep inject_dither rare (dist) so it
  //              spices up random tests without dominating them.
endclass
```

**The important idea:** the item describes *intent* ("turn forward 50 steps at this rate"),
not pin values. The driver owns the protocol. That separation is why the same sequence works
unchanged when you reuse this agent at Phase D, and it is the single most transferable thing
in this project.

---

## Step C4 — The protocol driver

```systemverilog
class quad_driver extends uvm_driver #(quad_item);

  `uvm_component_utils(quad_driver)

  virtual quad_if vif;
  quad_state_e    cur_state;     // the driver remembers where the "disk" is

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO(you): get vif, uvm_fatal if missing
  endfunction

  task run_phase(uvm_phase phase);
    // TODO(you): reset sequence — hold reset, park the pins at 00, release.
    //            Set cur_state = QUAD_S00.
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  task drive(quad_item item);
    // TODO(you):
    //   repeat (item.n_steps) begin
    //     walk_cycle(item.direction, item.clks_per_state);
    //   end
    //   if (item.inject_dither) dither(item.dither_state, item.dither_count,
    //                                  item.clks_per_state);
  endtask

  // Walk one full quadrature cycle from cur_state, in the given direction.
  task walk_cycle(quad_dir_e d, int unsigned hold);
    // TODO(you):
    //   forward order:  00 -> 10 -> 11 -> 01 -> 00
    //   reverse order:  00 -> 01 -> 11 -> 10 -> 00
    //   For each state: drive ch_a/ch_b through drv_cb, then hold for `hold`
    //   clocks, and update cur_state.
    //
    // Hint: a next_state() function in dut_pkg keeps this readable and gives
    //       the monitor something to reuse:
    //         function automatic quad_state_e quad_next(quad_state_e s, bit fwd);
    //
    // Hint: driving through the clocking block is nonblocking —
    //         vif.drv_cb.ch_a <= a;  vif.drv_cb.ch_b <= b;
    //         repeat (hold) @(vif.drv_cb);
  endtask

  // Rattle at one state without net displacement: toggle ONE channel out and
  // back, `n` times.
  task dither(quad_state_e s, int unsigned n, int unsigned hold);
    // TODO(you):
    //   Move to state s first (walk partial cycles until cur_state == s).
    //   Then n times: toggle one channel, hold, toggle it back, hold.
    //
    //   Which channel? At 00 you must toggle A (or B) — either produces the
    //   +1/-1 cancellation the design intends. At 11 either channel produces
    //   no pulses at all. Work out what you expect BEFORE you run it, then
    //   check. Predicting and confirming beats running and rationalizing.
  endtask

endclass
```

### Gate C4

Run a directed test with `n_steps = 10, direction = FORWARD, clks_per_state = 5`. In the
waveform, verify:

- The Gray sequence is correct — exactly one channel changes per transition. **Never two.**
  A two-bit change is not a quadrature signal, and if your driver produces one you are
  testing a condition the hardware cannot generate.
- Each state is held for 5 clocks.
- `count` reaches 10.

An assertion is worth writing for the "one channel at a time" property, on the driver side:
a testbench that can generate illegal stimulus will eventually generate illegal stimulus, and
you will chase a phantom DUT bug for a day.

---

## Step C5 — The reconstruction monitor

The monitor watches `pulse` and `dir` and reports observed displacement. It is the first
monitor in this project that has to **assemble** a transaction from several cycles of
activity rather than sample one.

```systemverilog
class quad_obs extends uvm_sequence_item;
  int          n_pulses;
  int          net_displacement;    // sum of +1 / -1 over the window
  int unsigned observed_count;      // the DUT's count at the end of the window

  `uvm_object_utils_begin(quad_obs)
    `uvm_field_int(n_pulses,         UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(net_displacement, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(observed_count,   UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "quad_obs"); super.new(name); endfunction
endclass
```

Two monitoring strategies, and you want both:

**Per-pulse (fine-grained).** Every time `pulse` is high, publish a single-step observation
carrying `dir`. The scoreboard maintains a running expected count. Catches errors in the
cycle they occur.

**Per-item (coarse).** Publish a summary at the end of each driven item. Simpler, but a lost
count in the middle of a run cancelled by a spurious one at the end would slip through.

Do the per-pulse version. It is barely more code and dramatically better.

```systemverilog
  task run_phase(uvm_phase phase);
    // TODO(you):
    //   1. Wait for reset to deassert, THEN wait a settle window.
    //      The synchronizer has no reset (O-QUAD-4), so a_sync/b_sync are 'x
    //      for the first couple of clocks. Sampling during that window
    //      produces failures that are entirely your fault.
    //      Something like:  repeat (4) @(vif.mon_cb);
    //
    //   2. forever @(vif.mon_cb) if (vif.mon_cb.pulse) begin
    //        obs.n_pulses         = 1;
    //        obs.net_displacement = vif.mon_cb.dir ? +1 : -1;
    //        obs.observed_count   = ...;   // careful: count updates the NEXT edge
    //        ap.write(obs);
    //      end
    //
    //   3. On observed_count: pulse is high in cycle N, count updates at edge
    //      N+1. So either publish on the pulse and let the scoreboard apply a
    //      one-cycle delay, or sample count one edge later inside the monitor.
    //      Pick one and be consistent. Mixing them is how off-by-one bugs live
    //      in testbenches for years.
  endtask
```

### Gate C5

For a 10-step forward run, the monitor publishes exactly 10 observations, each with
`net_displacement = +1`. For a reverse run, 10 with `-1`. Check the count of observations,
not just the values.

---

## Step C6 — The scoreboard

```systemverilog
class quad_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(quad_scoreboard)

  uvm_analysis_imp #(quad_obs, quad_scoreboard) ap_imp;

  int expected_count;
  int n_checked, n_failed;

  function void write(quad_obs obs);
    // TODO(you):
    //   expected_count += obs.net_displacement;
    //   compare against obs.observed_count;
    //   uvm_error with BOTH values and the pulse number on mismatch.
  endfunction

  // TODO(you): handle reset. The scoreboard's expected_count must be zeroed
  //            when the DUT's is. Options:
  //              (a) the monitor publishes a reset event on its analysis port
  //              (b) the scoreboard watches the reset signal directly
  //            (a) is cleaner — the scoreboard should not need a virtual
  //            interface. Do (a).

  function void report_phase(uvm_phase phase);
    // TODO(you): summary, and uvm_error if n_checked == 0.
  endfunction

endclass
```

---

## Step C7 — The sequence library

This is where the phase pays off: the driver understands the protocol, so sequences can be
short and expressive.

| Sequence | Body | Checks |
|---|---|---|
| `quad_forward_seq` | One item, `direction = FORWARD`, random `n_steps` | count increases by `n_steps` |
| `quad_reverse_seq` | Same, reverse | count decreases |
| `quad_reversal_seq` | Several items alternating direction, random lengths | net displacement matches the sum |
| `quad_dither_seq` | `inject_dither = 1` at each of the four states, 100 rattles each | **net zero at `00`; zero pulses at `01`/`10`/`11`** |
| `quad_fast_seq` | `clks_per_state` swept from 8 down to 1 | find the knee (see below) |
| `quad_random_seq` | Randomly picks among the above | everything |

### The composing sequence

```systemverilog
class quad_random_seq extends uvm_sequence #(quad_item);
  `uvm_object_utils(quad_random_seq)

  rand int unsigned n_sub_seqs;
  constraint c { n_sub_seqs inside {[5:20]}; }

  task body();
    // TODO(you): repeat n_sub_seqs times, pick a sub-sequence at random and
    //            start it on the same sequencer:
    //
    //   quad_forward_seq fwd;
    //   case ($urandom_range(0,3))
    //     0: begin fwd = quad_forward_seq::type_id::create("fwd");
    //              fwd.start(m_sequencer); end
    //     ...
    //   endcase
    //
    // A sequence starting other sequences on the same sequencer is the
    // ordinary way to compose stimulus. You do NOT need a virtual sequencer
    // for this — that is for coordinating sequences across SEVERAL
    // sequencers, which this environment does not have.
    //
    // Knowing when you don't need a UVM feature is worth as much as knowing
    // how to use it.
  endtask
endclass
```

### `quad_fast_seq` — the interesting one

`02_design_under_test.md` O-QUAD-1 predicts that counts are lost when the `00` state lasts
fewer than two synchronized samples. Find the knee empirically:

```systemverilog
  task body();
    // TODO(you): for hold = 8 down to 1:
    //   drive N full cycles at that hold value
    //   record how many pulses the monitor saw versus N
    //   uvm_info the ratio
    //
    // Expect 1:1 down to hold = 2, then a cliff at hold = 1.
    // If the cliff is somewhere else, your latency model is wrong — go back
    // to §3 of 02_design_under_test.md and work out why. Either the analysis
    // or the RTL is not what you thought, and finding out which is the whole
    // point.
```

**This sequence should not fail the test.** It characterizes. Have it report the knee and
have the *test* assert only that the knee is at or below the value you declared in
R-QUD-6. Then write the number, the prediction, and the physical margin into
`docs/results.md`.

That paragraph — "predicted 12.5 M cycles/s from the synchronizer depth and lock-clear
requirement, measured 12.5 M, physical maximum is 8.5 k, margin 1470×" — is the single most
credible thing in the whole project. It shows you predicted a behaviour from the RTL,
designed an experiment, and confirmed it.

---

## Step C8 — Assertions

```systemverilog
module first_value_priority_sva (
  input logic       clk, reset,
  input logic       pulse, dir,
  input logic [1:0] a_sync, b_sync,
  input logic signed [31:0] count       // from the sibling directional_counter
);

  default clocking @(posedge clk); endclocking

  // Every property here needs `disable iff (reset)` AND protection from the
  // synchronizer's x window (O-QUAD-4). A settle flag works well:
  logic settled;
  always_ff @(posedge clk, posedge reset)
    if (reset) settled <= 1'b0;
    else       settled <= 1'b1;    // extend to a few cycles if you see x-related noise

  // TODO(you): a_pulse_one_cycle
  //   pulse |=> !pulse      (never high two cycles running, O-QUAD-3)

  // TODO(you): a_count_moves_on_pulse
  //   pulse |=> (count == $past(count) + (dir ? 1 : -1))
  //   Careful: dir must be sampled in the same cycle as the pulse, so
  //   $past(dir) inside the consequent. Work out the exact cycle alignment;
  //   getting this right is most of the value of writing it.

  // TODO(you): a_count_stable_without_pulse
  //   !pulse |=> count == $past(count)

  // TODO(you): a_dir_stable_between_pulses
  //   !pulse |=> dir == $past(dir)      (O-QUAD-5)

  // TODO(you): a_no_double_channel_change
  //   Not a DUT property — a STIMULUS property. Assert that a_sync and b_sync
  //   never change in the same cycle. If it fires, your driver produced an
  //   illegal quadrature transition, and you want to know that immediately
  //   rather than after two days of blaming the decoder.
  //   Assertions that check the testbench are a real technique, not a hack.

endmodule
```

---

## Step C9 — Transition coverage

Ordinary coverpoints tell you which states you visited. **Transition bins** tell you which
edges you traversed — which is what actually matters for a state machine.

```systemverilog
covergroup cg_quad_state @(posedge clk);
  option.per_instance = 1;

  cp_state: coverpoint {a_sync[0], b_sync[0]} {
    bins s00 = {2'b00};
    bins s10 = {2'b10};
    bins s11 = {2'b11};
    bins s01 = {2'b01};

    // TODO(you): all 16 transitions.
    //   bins t_00_10 = (2'b00 => 2'b10);
    //   ... and so on for every ordered pair, including the self-transitions
    //   (2'b00 => 2'b00), which represent "held at this state".
    //
    //   Then think about which of the 16 are actually reachable with legal
    //   quadrature stimulus. The diagonal jumps — 00 => 11 and 10 => 01 —
    //   require BOTH channels to change in one clock, which a real encoder
    //   cannot do. Two legitimate treatments:
    //     (a) ignore_bins with a comment, arguing physical impossibility, or
    //     (b) leave them in and write a test that deliberately generates them,
    //         to characterize what the decoder does with a corrupt input.
    //
    //   (b) is more interesting and is a genuine robustness question: what
    //   SHOULD the decoder do if the encoder cable glitches? Try it, record
    //   the answer. That is a finding.
  }

  cp_pulse: coverpoint pulse { bins fired = {1}; bins idle = {0}; }
  cp_dir:   coverpoint dir   { bins up = {1};    bins down = {0}; }

  // TODO(you): cross cp_dir with a step-rate coverpoint so you can prove you
  //            exercised both directions at both fast and slow rates.
endgroup
```

### Gate C9

100% transition coverage on the legal transitions, with the illegal ones either
`ignore_bins`'d (with a written argument) or deliberately covered by a robustness test whose
result you recorded.

---

## Phase C gate

- [ ] All seven tests pass across twenty seeds.
- [ ] Dither test proves net-zero displacement over 100 rattles at `00`, and zero pulses at
      `01`, `10`, `11`.
- [ ] `quad_fast_seq` located the knee, and it matches the prediction in
      `02_design_under_test.md` §3 — or you found out why it does not.
- [ ] Transition coverage 100% or fully argued.
- [ ] All five assertions bound and observed firing against broken RTL.
- [ ] `docs/results.md` records O-QUAD-1 through O-QUAD-6 with verdicts.
- [ ] Committed.

### Explain these out loud

1. Why does `quad_item` carry `n_steps` and `clks_per_state` rather than `ch_a` and `ch_b`?
2. Your monitor sees `pulse` in cycle N and `count` changes at N+1. How did you handle that,
   and what would break if you had not?
3. Why is the diagonal transition `00 => 11` unreachable with a real encoder, and what did
   you decide to do about it in coverage?
4. What is a virtual sequencer for, and why does this environment not need one?
5. You wrote an assertion that checks your own driver. Why is that not cheating?
6. The scoreboard checks `count`, but coverage and assertions use internal probes. Defend
   that split.
