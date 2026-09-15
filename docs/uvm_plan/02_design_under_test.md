# The Design Under Test

The reference document for the whole project. Every golden-model formula your scoreboards
call, every corner case your constraints target, and every assertion you bind comes from
here. Read it once now; keep it open for the next six weeks.

Everything below was derived from the RTL as written in
`enel441_453_lab.srcs/sources_1/new/`. Derivations are shown so you can re-check them
rather than trust them — and you should re-check them, because a golden model you cannot
defend is worse than no golden model.

---

## 0. System overview

```
                                    top_module
  ┌────────────────────────────────────────────────────────────────────────────┐
  │                                                                            │
  │  sw[3:0] ─┐                                                                │
  │  btn[1:0]─┤  enel453_lab_initializer ──► reference (signed 32) ──┐          │
  │           │   (debounce ×6, ROM playback, clock_div @20 Hz)      │          │
  │           └─────────────────────────────────────────────────────┐│          │
  │                                                       K = 1 ────┤│          │
  │  ┌──────────────────────── prop_ctrl_pwm ────────────────────── ▼▼───────┐  │
  │  │                                                                       │  │
  │  │  ch_a ─┐                                                              │  │
  │  │  ch_b ─┴─► decoder_to_32_bit ─► position ─┐                           │  │
  │  │            ├ first_value_priority         │                           │  │
  │  │            │   └ synchronizer ×2          ▼                           │  │
  │  │            └ directional_counter      controller ─► error_scaled      │  │
  │  │                                        (ref reg, ×k, truncate 32)     │  │
  │  │                                             │                         │  │
  │  │                                             ▼                         │  │
  │  │                                   magnitude_clamp ──► pwm_cmp, dir    │  │
  │  │                                    (CLAMP = 2^BITS-1)  │       │      │  │
  │  │                        clock_div ──► clk_divd          │       ├──► motor_in1 = dir
  │  │                         (+ BUFG)         │             │       └──► motor_in2 = ~dir
  │  │                                          ▼             ▼              │  │
  │  │                                      pwm_n_bit ──────────────► motor_en  │
  │  │                                                        │              │  │
  │  │                    led_status ◄────────────────────────┘              │  │
  │  │                     └ bar_encoder ─────────────────────────► led[15:0]│  │
  │  │                                                                       │  │
  │  │                    status_7seg ◄── reference ──────────────► seg, an  │  │
  │  │                     └ clock_div (+ BUFG)                              │  │
  │  └───────────────────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────────────────┘
```

**In scope for this project (the ladder):** `pwm_n_bit`, `magnitude_clamp`,
`decoder_to_32_bit` (with `first_value_priority`, `synchronizer`, `directional_counter`),
and `prop_ctrl_pwm` as the integration DUT.

**Out of scope:** `enel453_lab_initializer`, `debounce`, `status_7seg`, `bar_encoder` and
`led_status` as standalone DUTs, and `top_module`. `led_status` and `status_7seg` are
*present* inside the Phase D DUT, so you will observe them, but you are not verifying them
to closure. Say that in `docs/results.md`.

**Clock domains.** Two. Everything runs on `clk` (100 MHz) except `pwm_n_bit`, which runs on
`clk_divd` from `clock_div`, and the `status_7seg` digit scanner, which runs on its own
divided clock. This matters at Phase D — see §6.

---

## 1. `pwm_n_bit`

```systemverilog
module pwm_n_bit #(parameter int BITS = 12, parameter int THRESHOLD = 0) (
    input  logic            clk, reset,
    input  logic [BITS-1:0] duty,
    output logic            pwm_out
);
    logic [BITS-1:0] D, Q;
    assign pwm_out = (Q <= duty) && duty && (duty > THRESHOLD);
    always_ff @(posedge clk, posedge reset) begin
        if (reset) Q <= 0; else Q <= D;
    end
    always_comb D = Q + 1;
endmodule
```

`Q` is a free-running counter over `0 .. 2**BITS-1`, wrapping naturally on overflow.

### Golden model — derivation

`pwm_out` is high exactly when the command clears the deadband **and** the counter has not
yet passed it:

```
(duty > THRESHOLD) && (Q <= duty)
```

The two tests are independent: `THRESHOLD` gates the *command*, while `Q` is compared only
against `duty`. So once the deadband is cleared the pulse runs contiguously from `Q = 0` to
`Q = duty` inclusive — `duty + 1` counts — and otherwise the output is flat low for the
whole period.

```
high_cycles(duty) = (duty > THRESHOLD) ? duty + 1 : 0
period            = 2**BITS   clocks of clk_divd, exactly
duty_fraction     = high_cycles / 2**BITS
```

The `&& duty` term in the RTL is redundant — for any `THRESHOLD >= 0`, `duty > THRESHOLD`
already implies `duty >= 1`. Do not model it.

> **This is a local modification, not upstream RTL.** See `rtl/PROVENANCE.md` §2. Upstream
> reads `(Q < duty) && (Q > THRESHOLD)`, which gives `max(0, duty − THRESHOLD − 1)` and
> cannot reach 100%. The change was made deliberately to resolve **R-PWM-4**. If you ever
> re-sync `rtl/` from `research_2026`, this entire section reverts with it — and so does
> your golden model, your scoreboard and `a_out_relation`.

Sanity checks to verify before trusting this. These are *measured* from the RTL at
`BITS = 8`, not hand-derived — re-measure them yourself at Gate A2:

| `duty` | `THRESHOLD` | `high_cycles` | Why |
|---:|---:|---:|---|
| 0 | 0 | 0 | `0 > 0` is false — deadband |
| 1 | 0 | 2 | `Q ∈ [0, 1]` |
| 2 | 0 | 3 | `Q ∈ [0, 2]` |
| 255 | 0 | 256 | `Q ∈ [0, 255]` — the entire period, 100% |
| 14 | 14 | 0 | `14 > 14` is false — deadband |
| 15 | 14 | 16 | `Q ∈ [0, 15]` |
| 16 | 14 | 17 | `Q ∈ [0, 16]` |
| 255 | 14 | 256 | `Q ∈ [0, 255]` — 100% |

### Observations to record

**O-PWM-1 — the duty map is offset by one, and 0% is reachable only through the deadband.**
`Q = duty` is counted, so a command of `duty` produces `duty + 1` high cycles, not `duty`.
Full scale *is* reachable: `duty = 2**BITS − 1` gives `2**BITS` high cycles, exactly 100%.
But the smallest **non-zero** output is `(THRESHOLD + 2) / 2**BITS`. With `top_module`'s
`BITS = 8, THRESHOLD = 14` the output jumps straight from 0 to `16/256 = 6.25%` at
`duty = 15` — the reachable set is `{0} ∪ {16/256 … 256/256}` and there is no way to ask
for `1/256`. At Phase D `duty` is a clamped error magnitude, so that step is the minimum
motor effort the loop is able to command. Whether it matters is a **spec question, not an
RTL question**.

> **This observation replaced the upstream one.** The original O-PWM-1 was "100% duty is
> unreachable" — `240/256 = 93.75%` at `THRESHOLD = 14`, `254/256 = 99.2%` at
> `THRESHOLD = 0` — and it is the reason R-PWM-4 exists. The fix recorded in
> `rtl/PROVENANCE.md` §2 closed it and left this smaller offset behind. **Record both** in
> `docs/results.md`: a finding you fixed, plus the residual finding the fix introduced, is
> a better and more honest story than either on its own.

**O-PWM-2 — deadband.** Any `duty <= THRESHOLD` produces a permanently low output. At
Phase D, `duty = pwm_cmp = |error|` clamped, so with `THRESHOLD = 14` the motor does not
move until the position error reaches 15 encoder ticks.

**O-PWM-3 — check the `THRESHOLD` units.** `top_module` sets
`THRESHOLD = 5 * 512 / 180 = 14` (integer division). But `status_7seg` converts ticks to
degrees with `deg = ticks * 90 / 128`, i.e. **512 ticks per 360°**, or 0.703° per tick. Under
that convention 5° is `5 * 512 / 360 = 7` ticks, not 14. The `180` in the `THRESHOLD`
expression implies 512 ticks per *half* revolution. One of the two is wrong, and the
consequence is a deadband covering errors up to 14 ticks ≈ 9.8°, with the first command
that moves the motor at 15 ticks ≈ 10.5° — roughly double the 5° the expression appears to
intend. **Investigate and record the answer** — you have the hardware, so you can settle it.

**O-PWM-4 — parameter trap.** `duty` is unsigned; `THRESHOLD` is a signed `int` parameter.
In SystemVerilog a comparison with any unsigned operand is evaluated unsigned, so a negative
`THRESHOLD` becomes a huge unsigned value, `duty > THRESHOLD` is false for every `duty`, and
`pwm_out` is stuck low forever. The `&& duty` term does not rescue it. Add
`initial assert (THRESHOLD >= 0 && THRESHOLD < 2**BITS)` to the environment.

**O-PWM-5 — `duty` changing mid-period.** `duty` is a combinational input to `pwm_out`, so a
mid-period change takes effect immediately and can produce a runt pulse or an extended one.
That is normal for this PWM style but is worth a directed test and a written note.

### Verification approach

| | |
|---|---|
| **Stimulus** | Random `duty`, held for a whole number of periods; plus a directed test that changes `duty` mid-period. |
| **Checking** | Monitor counts high cycles over one full period; scoreboard compares to `expected_pwm_high()`. Assertion checks the instantaneous relation every cycle. |
| **Coverage** | `duty` bins: `0`, `1`, `THRESHOLD`, `THRESHOLD±1`, low/mid/high bands, `2**BITS-1`, `2**BITS-2`. |

---

## 2. `magnitude_clamp`

```systemverilog
module magnitude_clamp #(parameter int CLAMP_VAL) (
    input  logic signed [31:0]                 value,
    output logic [$clog2(CLAMP_VAL+1)-1:0]     clamped_value,
    output logic                               dir
);
    logic [31:0] value_abs;
    always_comb begin
        if (value < 0) begin value_abs = ~value + 1; dir = 1; end
        else           begin value_abs =  value;     dir = 0; end
    end
    always_comb begin
        if (value_abs > CLAMP_VAL) clamped_value = CLAMP_VAL;
        else                       clamped_value = value_abs[$clog2(CLAMP_VAL+1)-1:0];
    end
endmodule
```

### Golden model

```
dir           = (value < 0)                      // signed comparison; value == 0 gives dir = 0
magnitude     = |value|  as a 33-bit-safe unsigned quantity
clamped_value = min(magnitude, CLAMP_VAL)
```

### Observations to record

**O-CLAMP-1 — `INT_MIN` works, but not for an obvious reason.** For
`value = 32'h8000_0000` (−2 147 483 648), `~value + 1` returns `32'h8000_0000` again — two's
complement negation of the most-negative value overflows back to itself. But `value_abs` is
*unsigned*, so that bit pattern reads as 2 147 483 648, which is the correct magnitude, and
it exceeds any sane `CLAMP_VAL` so it saturates. The result is right. Make sure your golden
model computes the magnitude in a wide enough type (use a 64-bit `longint` intermediate) or
your model will be the thing that is wrong.

**O-CLAMP-2 — output width is always sufficient.** The port is
`$clog2(CLAMP_VAL+1)` bits wide, which holds `0 .. 2**ceil(log2(CLAMP_VAL+1)) - 1`, and that
upper bound is always `>= CLAMP_VAL`. Check three cases: `CLAMP_VAL = 100 → 7 bits (0..127)`,
`255 → 8 bits (0..255)`, `4095 → 12 bits (0..4095)`. No truncation.

**O-CLAMP-3 — parameter trap.** `CLAMP_VAL = 0` gives `$clog2(1) - 1 = -1` and an illegal
`logic [-1:0]` port. Assert `CLAMP_VAL >= 1` in the environment.

**O-CLAMP-4 — mixed-sign comparison.** `value_abs` is unsigned and `CLAMP_VAL` is a signed
`int`, so `value_abs > CLAMP_VAL` is an *unsigned* comparison. Harmless for positive
`CLAMP_VAL`, catastrophic for negative. Covered by O-CLAMP-3's assertion.

### Corner values your constraints must hit

`0`, `+1`, `−1`, `+CLAMP_VAL`, `−CLAMP_VAL`, `+(CLAMP_VAL+1)`, `−(CLAMP_VAL+1)`,
`32'h7FFF_FFFF`, `32'h8000_0000`.

Uniform random over 2³² will essentially never hit these. That is the entire lesson of
Phase B: **unconstrained random is not the same as good random.**

---

## 3. `decoder_to_32_bit` — the interesting one

Composed of `first_value_priority` (direction + pulse generation, with two `synchronizer`
instances) and `directional_counter`.

### This is *not* a 4× quadrature decoder

A textbook quadrature decoder counts all four state transitions per cycle. This one counts
**only transitions that touch the `00` state**, and it counts **one pulse per full
quadrature cycle**. Read the RTL conditions carefully:

```
UP   pulse when:  (a_sync rose and b_sync is low)     // 00 → 10
              or  (b_sync fell and a_sync is low)     // 01 → 00

DOWN pulse when:  (b_sync rose and a_sync is low)     // 00 → 01
              or  (a_sync fell and b_sync is low)     // 10 → 00
```

plus a lock mechanism:

- An UP pulse sets `up_lock` and clears `down_lock`; a DOWN pulse does the reverse.
- Both locks clear only when A **and** B have been observed low for **two consecutive
  samples** — i.e. when the encoder is genuinely resting at the `00` detent.
- A pulse is suppressed if its own lock is already set.

### Walk the forward cycle: `00 → 10 → 11 → 01 → 00`

| Transition | UP condition | DOWN condition | Lock state | Pulse? |
|---|---|---|---|---|
| `00 → 10` | A rose, B low → **true** | — | `up_lock` clear | **UP** |
| `10 → 11` | B rose but A high → false | B rose but A high → false | | no |
| `11 → 01` | B did not fall → false | A fell but B high → false | | no |
| `01 → 00` | B fell, A low → **true** | — | `up_lock` **set** | suppressed |
| at `00` ×2 | — | — | both locks clear | — |

**One UP pulse per forward revolution of the quadrature cycle.** The reverse cycle
`00 → 01 → 11 → 10 → 00` is exactly symmetric: one DOWN pulse, generated at `00 → 01`, with
the `10 → 00` transition suppressed by `down_lock`.

### Dither behaviour — verify this, it is the design's whole point

**Dither at the `00` detent** (A toggles `0 → 1 → 0`, B stays low):

- `00 → 10`: UP pulse. `up_lock` set, `down_lock` cleared.
- `10 → 00`: DOWN condition true (A fell, B low), and `down_lock` was just cleared → **DOWN
  pulse**. Net displacement **zero**.
- Then two cycles at `00` clear both locks.

That +1/−1 cancellation is deliberate: a disk vibrating at a detent must not accumulate
count. Prove it with a hundred rattles and assert the final `count` is unchanged.

**Dither at `11`, `10` or `01`**: no pulses at all, because every UP and DOWN condition
requires the *other* channel to be low. Verify by observing zero pulses.

### Latency — your monitor needs this exactly

```
ch_a/ch_b changes
   │
   ├─ edge 1: synchronizer int_wire <= in
   ├─ edge 2: synchronizer out <= int_wire        → a_sync[0]/b_sync[0] updated
   ├─ edge 3: first_value_priority evaluates      → pulse high for one cycle
   └─ edge 4: directional_counter, en = pulse     → count updated
```

**Four `clk` edges from a pin change to a `count` change.** `pulse` is high for exactly the
one cycle between edges 3 and 4.

### O-QUAD-1 — the maximum encoder rate, and where counts are lost

The lock clears only when `00` is observed for **two consecutive synchronized samples**. If
the disk spins fast enough that the `00` quarter-cycle lasts less than two `clk` periods
after synchronization, the lock never clears and **every subsequent pulse is suppressed** —
the counter silently stops.

At 100 MHz, two clocks is 20 ns, so the `00` state must last ≥ 20 ns, giving a full
quadrature cycle of ≥ 80 ns, i.e. ≤ 12.5 M cycles/s. At 512 ticks per revolution that is
about 24 400 rev/s — orders of magnitude beyond any physical motor, so this is a
**verified margin, not a defect**. But finding it, quantifying it, and writing it down as
"verified correct operation up to X; degrades above X; physical maximum is Y; margin is Z"
is exactly what a verification engineer is paid to do. Build `quad_fast_seq` to find the
knee empirically and confirm it matches this arithmetic.

### O-QUAD-2 — the lock is visible two edges late

`up_lock[1] <= up_lock[0]` means the lock the condition actually tests (`up_lock[1]`) lags
the lock the pulse sets (`up_lock[0]`) by one clock. So there is a one-cycle window after a
pulse in which the lock is not yet visible. Work through whether a second pulse can slip
through in that window — the answer is no, because both UP conditions require an edge that
cannot repeat on the very next cycle, but *proving* that is a genuinely good exercise, and an
assertion (`pulse` never high two cycles running) makes it permanent.

### O-QUAD-3 — `pulse <= 0` sits above the reset branch

```systemverilog
always_ff @(posedge clk, posedge reset) begin
    pulse <= 0;              // default, outside the if(reset)
    if (reset) begin ... end
    else begin ... pulse <= 1; ... end
end
```

Legal — last nonblocking assignment in the block wins — and it is the idiomatic way to write
a one-cycle-pulse default. Worth an assertion so a future refactor cannot silently break it.

### O-QUAD-4 — `synchronizer` has no reset

```systemverilog
always_ff @(posedge clk) begin
    int_wire <= in;
    out      <= int_wire;
end
```

No reset branch, no initial value, so `a_sync[0]` and `b_sync[0]` are `x` for the first two
clocks of simulation. Your monitor and assertions must tolerate that: use
`disable iff (reset || !settled)` and have the environment hold off checking for a settle
window after reset deasserts. If you do not, you will spend an afternoon debugging a
"failure" that is just `x` propagation. On hardware this is fine — the flops power up to
some real value and converge within two clocks.

### O-QUAD-5 — `dir` holds between pulses

`ff1_wire` (which drives `dir`) is only written inside a pulse branch, so between pulses
`dir` retains the direction of the last counted step. Do not write an assertion that expects
`dir` to mean anything when `pulse` is low.

### O-QUAD-6 — counter overflow

`directional_counter` is a signed 32-bit counter with no saturation. It wraps at ±2³¹. Not
reachable in normal operation (that is 4 million revolutions), but a directed test that
forces the counter near the boundary and confirms clean wrap is cheap and shows you thought
about it.

### Verification approach

| | |
|---|---|
| **Stimulus** | A protocol driver that turns `(n_steps, direction, step_period, dither)` into a pin-level Gray sequence. |
| **Checking** | Monitor reconstructs displacement from `pulse`/`dir`; scoreboard holds the running expected count and compares against `count`. |
| **Coverage** | All 16 `{a_sync, b_sync}` state transitions; direction × step-rate cross; lock set/clear paths; dither at each of the four states. |
| **Assertions** | `pulse` never high 2 cycles running; `count` changes only when `pulse` was high; delta is exactly ±1; `count` stable while `pulse` low. |

---

## 4. `controller` — the signed/unsigned question, answered

```systemverilog
logic signed [31:0] ref_position, error;
logic signed [63:0] error_scaled_int;

always_ff @(posedge clk, posedge reset)
    if (reset) ref_position <= 0; else ref_position <= reference;

assign error            = position - ref_position;
assign error_scaled_int = error * k;              // k is UNSIGNED [31:0]
assign error_scaled     = error_scaled_int[31:0];
```

Your own comment in the RTL asks "are you multiplying signed or unsigned?". Here is the
answer, and it is worth understanding properly because it is a classic interview question.

### The multiply really is unsigned

`error` is `logic signed [31:0]`; `k` is `logic [31:0]`, **unsigned**. In SystemVerilog, if
*any* operand of a binary operator is unsigned, the operation is unsigned and both operands
are treated as unsigned. The assignment target is 64 bits, so both operands are extended to
64 bits — and because the expression is unsigned, `error` is **zero-extended**, not
sign-extended.

So for `error = −256` (`32'hFFFF_FF00`) and `k = 1`:

```
64-bit unsigned operands:  0x0000_0000_FFFF_FF00  ×  0x0000_0000_0000_0001
product:                   0x0000_0000_FFFF_FF00
error_scaled = [31:0]:     0xFFFF_FF00  =  −256 as signed 32   ✓
```

And for `k = 3`:

```
product:                   0x0000_0002_FFFF_FD00
error_scaled = [31:0]:     0xFFFF_FD00  =  −768 as signed 32   ✓
```

### Why it is correct anyway

Two's-complement multiplication and unsigned multiplication produce **identical low-order
bits**. Formally, for any 32-bit patterns `a` and `b`:

```
(a ×_signed b)  mod 2³²  ==  (a ×_unsigned b)  mod 2³²
```

Truncating to `[31:0]` *is* taking the result mod 2³². So `error_scaled` carries the correct
signed product **whenever that product fits in 32 signed bits**, regardless of the
signedness of the multiply. This is a satisfying thing to prove with a few thousand random
`(error, k)` pairs rather than argue about at a whiteboard — make it one of your first
Phase D scoreboard results.

### O-CTRL-1 — the real hazard is overflow

The equivalence above holds *modulo 2³²*. Once `|error × k| ≥ 2³¹` the truncation wraps and
the sign bit flips:

```
overflow when   |error| × k  ≥  2³¹  =  2 147 483 648
```

With a full revolution of error (512 ticks) that is `k ≥ 4 194 304`. `top_module` hardcodes
`K = 1`, so the lab never sees it — but `k` is a 32-bit input port with no documented range.

**A wrapped `error_scaled` flips the sign bit, so `dir` inverts and the motor drives away
from the target at full effort.** That is a runaway, not a degradation.

This is the judgement call of the project: **bug, or out of spec?** There is no correct
answer until you write down a spec. Your options, all defensible:

1. Declare a legal range for `k` in the verification plan, constrain to it, and add an
   assertion that fires if the product ever overflows. Document the range as a
   design constraint.
2. Call it a defect and recommend a saturating multiply
   (`error_scaled = clamp(error*k, −2³¹, 2³¹−1)`), noting the extra logic cost.
3. Both — constrain the tests, and file the recommendation.

Whichever you choose, **write the argument down**. Option 3 with a clear rationale is what a
real DV engineer submits.

### O-CTRL-2 — `error_scaled_int`'s upper bits are garbage

`error_scaled_int` is declared `signed [63:0]` but holds a zero-extended unsigned product, so
for negative errors its 64-bit value is a large positive number that means nothing. Only
`[31:0]` is meaningful. If anyone ever widens the truncation — say to `[47:0]` — the design
breaks silently. Worth a comment in the RTL and a line in your results document.

### O-CTRL-3 — one clock of reference latency

`ref_position` is registered, so `error` reflects the reference from the **previous** clock.
Your golden model must delay `reference` by exactly one `clk` before subtracting, or your
scoreboard will report a spurious mismatch on every reference change. `position` is *not*
delayed — it comes straight from the counter.

---

## 5. `led_status`, `bar_encoder`, `status_7seg` — observed, not verified to closure

Present inside the Phase D DUT. Model them if you want extra checking; do not claim you
verified them.

### `bar_encoder` is logarithmic, not linear

```systemverilog
bar[BITS-1] = value[BITS-1];
for (int i = BITS-2; i >= 0; i--) bar[i] = bar[i+1] | value[i];
```

Unrolled, `bar[i] = OR(value[BITS-1 : i])`, so `bar[i]` is set iff any bit at or above
position `i` is set. The result is all-ones from the **most significant set bit** down to
bit 0:

| `value` | `bar` | LEDs lit |
|---|---|---:|
| `0x00` | `0x00` | 0 |
| `0x01` | `0x01` | 1 |
| `0x02` | `0x03` | 2 |
| `0x40` | `0x7F` | 7 |
| `0x80` | `0xFF` | 8 |

Lit count = `floor(log2(value)) + 1` for `value > 0`. It is a log meter. Whether that is what
you wanted for a PWM effort display is a design question worth a sentence in your results.

### O-LED-1 — the bar aliases at `BITS > 8`

`led_status` takes `pwm_cmp[7:0]` only. At `top_module`'s `BITS = 8` that is the whole
command and everything is fine. At `prop_ctrl_pwm`'s **default** `BITS = 12`, a `pwm_cmp` of
`0x100` (256) presents `pwm_cmp[7:0] = 0x00` and the LED bar goes dark at high effort. A
genuine defect in any configuration other than the one the board uses — worth reporting, and
a good example of a parameter-dependent bug that only appears when you verify across the
parameter space rather than at one operating point.

### O-7SEG-1 — the degree display wraps at 1023 ticks

```systemverilog
assign reference_deg = (abs_reference[9:0] * 18'd90) / 18'd128;
```

Only the low 10 bits of the magnitude are used, so a reference beyond ±1023 ticks (±719°)
displays a wrapped value. The scale factor `90/128 = 0.703 °/tick` is consistent with 512
ticks per revolution, which is what makes O-PWM-3's `THRESHOLD` expression suspicious.

---

## 6. `clock_div`, `BUFG`, and simulation runtime

```systemverilog
localparam int TICKS = (CLK_FREQ_HZ/DESIRED_CLK_FREQ_HZ)/2;
localparam int BITS  = $clog2(TICKS);
logic clk_int = 1'b0;
logic [BITS-1:0] counter = '0;
// counter++ ; on counter == TICKS-1 toggle clk_int and reset counter
BUFG bufg_inst (.I(clk_int), .O(clk_out));
```

Output frequency is `CLK_FREQ_HZ / (2 × TICKS)`, approximately `DESIRED_CLK_FREQ_HZ` up to
integer-division error.

### O-DIV-1 — parameter trap, and it is a hard elaboration failure

`BITS = $clog2(TICKS)`. If `TICKS` ever resolves to **1**, `$clog2(1) = 0` and the counter is
declared `logic [-1:0]` — illegal, and your simulation will not elaborate. If `TICKS`
resolves to **0** the counter never matches `TICKS-1` and the clock never toggles. Put
`initial assert (TICKS >= 2) else $fatal(...)` in your environment; it will save you at
Phase D when you start overriding parameters for speed.

### O-DIV-2 — `BUFG` needs handling in simulation

`BUFG` is a Xilinx primitive that does not exist in a plain SystemVerilog compile. Two
options, both fine:

- **A two-line stub** in `tb/common/bufg_stub.sv` (`assign O = I;`). Portable, keeps the flow
  simulator-agnostic. **Recommended** — and note the substitution in your README so nobody
  mistakes it for silicon behaviour.
- **`-L unisims_ver`** on `xelab`, plus `glbl` as an extra top module. Faithful, XSim-specific.

### The runtime problem, and the standard fix

At production parameters, `prop_ctrl_pwm` with `BITS = 8, PWM_CLK_FREQ_HZ = 490`:

```
CLK_FREQ_HZ  = 490 × (2^8 - 1)   = 124 950 Hz          (the clock_div target)
TICKS        = (100e6 / 124 950)/2 = 800/2 = 400
clk_divd     = 100e6 / 800        = 125 kHz
PWM period   = 256 × 800          = 204 800 clk cycles ≈ 2.048 ms
```

Ten PWM periods per test × fifty seeds is 100 million clock cycles of simulation. That is
not a regression, that is an overnight job.

**Override the parameter for simulation.** Pick `PWM_CLK_FREQ_HZ = 98 000`:

```
CLK_FREQ_HZ  = 98 000 × 255       = 24 990 000 Hz
TICKS        = (100e6 / 24 990 000)/2 = 4/2 = 2       ← still ≥ 2, satisfies O-DIV-1
clk_divd     = 100e6 / 4          = 25 MHz
PWM period   = 256 × 4            = 1024 clk cycles ≈ 10.24 µs
```

**A 200× speedup with the DUT logic completely unchanged.** The divider ratio changes; every
piece of behaviour you are actually verifying does not. Then run one test at production
parameters as a sanity check, and say in your results that you did.

This technique — verify the timing-independent behaviour fast, then confirm the real
configuration once — is standard practice and worth being able to explain. The trap to avoid
is overriding a parameter that changes the behaviour you are checking; here you are only
changing how many clocks a period takes.

---

## 7. Consolidated observation register

Copy this into `docs/results.md` and fill in the verdict column as you go.

| ID | Module | Observation | Verdict | Evidence |
|---|---|---|---|---|
| O-PWM-1 | `pwm_n_bit` | Duty map offset by one; 0% reachable only via the deadband (upstream: 100% unreachable, fixed — see `rtl/PROVENANCE.md` §2) | | |
| O-PWM-2 | `pwm_n_bit` | Deadband for `duty <= THRESHOLD` | | |
| O-PWM-3 | `top_module` | `THRESHOLD` unit inconsistent with `status_7seg` (180 vs 360) | | |
| O-PWM-4 | `pwm_n_bit` | Negative `THRESHOLD` breaks the output (unsigned compare) | | |
| O-PWM-5 | `pwm_n_bit` | Mid-period `duty` change produces runt/extended pulse | | |
| O-CLAMP-1 | `magnitude_clamp` | `INT_MIN` handled correctly via unsigned reinterpretation | | |
| O-CLAMP-3 | `magnitude_clamp` | `CLAMP_VAL = 0` is an illegal parameter | | |
| O-QUAD-1 | `first_value_priority` | Counts lost above ~12.5 M quadrature cycles/s | | |
| O-QUAD-2 | `first_value_priority` | Lock visible two edges late | | |
| O-QUAD-4 | `synchronizer` | No reset; `x` for two clocks at time zero | | |
| O-QUAD-6 | `directional_counter` | No saturation; wraps at ±2³¹ | | |
| O-CTRL-1 | `controller` | `error × k` overflow flips `dir` → runaway | | |
| O-CTRL-2 | `controller` | `error_scaled_int` upper 32 bits meaningless | | |
| O-LED-1 | `led_status` | Bar aliases on `pwm_cmp[7:0]` when `BITS > 8` | | |
| O-7SEG-1 | `status_7seg` | Degree display wraps above 1023 ticks | | |
| O-DIV-1 | `clock_div` | `TICKS < 2` fails elaboration | | |

Verdict is one of **bug** (design is wrong), **limitation** (design is right, behaviour is
bounded, document it), or **out of spec** (input was outside the declared legal range).
Every row needs a one-line argument. That table, filled in, is the single most credible
artifact this project produces.
