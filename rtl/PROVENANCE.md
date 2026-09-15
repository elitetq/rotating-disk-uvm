# RTL Provenance

The `rtl/` directory is a **vendored copy** — these files are not authored here. This
document records where they came from so that "has the copy drifted from the original?"
is a question with an answer.

## Source

| | |
|---|---|
| Repo | `https://github.com/elitetq/research_2026` |
| Branch | `mvp_changes` |
| Commit | `01471d4` ("changed intro slightly", 2026-08-19) |
| Path in repo | `enel441_453_lab/Rotating Disk/enel441_453_lab.srcs/sources_1/new/` |
| Local checkout | `/home/jonar/research_2026/enel441_453_lab` |
| Date copied | 2026-09-08 |

At the time of copying, `01471d4` was the tip of `mvp_changes` and the source tree was
clean, so the vendored files match that commit byte-for-byte except where noted below.

## What was copied

Twelve modules, the full `prop_ctrl_pwm` hierarchy plus the board-level display/status
blocks:

`bar_encoder.sv`, `clock_div.sv`, `controller.sv`, `decoder_to_32_bit.sv`,
`directional_counter.sv`, `first_value_priority.sv`, `led_status.sv`,
`magnitude_clamp.sv`, `prop_ctrl_pwm.sv`, `pwm_n_bit.sv`, `status_7seg.sv`,
`synchronizer.sv`

## What was deliberately left behind

- `top_module.sv` — board top level. Out of scope; the UVM work targets
  `prop_ctrl_pwm` and below.
- `debounce.sv`, `enel453_lab_initializer.sv` — only instantiated by `top_module`.
- `tracking_mem.txt`, `xvlog.pb` — data/build artifacts.

## Local modifications (divergence from upstream)

These are **not** upstream. None of them have been pushed back to `research_2026` yet.
There are two independent changes, made for different reasons — keep them separate when
you do push, because only the first is unambiguously a bug fix.

### 1. Step 0.1 — the open control loop (applied 2026-09-14)

From `docs/uvm_plan/00_roadmap.md` §0.1.

- **`controller.sv`** — dropped `position` from the internal `logic signed [31:0]`
  declaration on line 34. It was declared both as an internal signal and as an ANSI
  input port, so the port was shadowed and tied off.

  ```diff
  - logic signed [31:0]            position, ref_position, error;
  + logic signed [31:0]            ref_position, error;
  ```

- **`prop_ctrl_pwm.sv`** — added the missing `.position(position)` connection to the
  `CONTROLLER` instance (line ~57).

  ```diff
        .reference(reference),
  +     .position(position),
        .k(k),
  ```

Together these close the proportional loop. Before the fix, `error` evaluated to
`-ref_position` forever regardless of actual disk position — the loop was open, and
Vivado flagged it as three synthesis warnings (`Synth 8-11121`, `8-7071`, `8-7023`).

### 2. R-PWM-4 — full-scale duty and a clean deadband (applied 2026-09-14)

This is a **deliberate design change**, not a repair of a synthesis warning. It resolves
requirement **R-PWM-4** in `docs/uvm_plan/03_verification_plan.md` §2 the way that document
anticipated: *"If the answer is '100% is required', you have found a bug and should propose
the fix (`Q <= duty` instead of `Q < duty`, which shifts the whole mapping by one)."*

- **`pwm_n_bit.sv`, line 31** — the output relation.

  ```diff
  - assign pwm_out          = (Q < duty) && (Q > THRESHOLD);
  + assign pwm_out          = (Q <= duty) && duty && (duty > THRESHOLD);
  ```

Two things changed, and they are worth separating:

| | Upstream | Here |
|---|---|---|
| Counter comparison | `Q < duty` | `Q <= duty` — counts `Q = duty`, so full scale is reachable |
| Deadband test | `Q > THRESHOLD` — clips the *counter* range | `duty > THRESHOLD` — gates the *command*, leaving the pulse contiguous from `Q = 0` |

Consequences, all confirmed in simulation at `BITS = 8`:

```
high_cycles(duty) = (duty > THRESHOLD) ? duty + 1 : 0        per 2**BITS clocks
```

- **100% duty is now reachable.** `duty = 2**BITS - 1` gives `2**BITS` high cycles.
  Upstream topped out at `240/256 = 93.75%` with `THRESHOLD = 14`.
- **The pulse now starts at `Q = 0`** instead of `Q = THRESHOLD + 1`. Upstream's pulse was
  offset into the period; the deadband and the pulse position were entangled in one
  expression. They are now independent.
- **The deadband boundary moved by one.** Upstream: output low for `duty <= THRESHOLD + 1`.
  Here: output low for `duty <= THRESHOLD`.
- **0% duty is only reachable through the deadband.** Because the map is `duty + 1`, the
  smallest non-zero output is `(THRESHOLD + 2) / 2**BITS`. With `THRESHOLD = 14` the output
  jumps from 0 to `16/256 = 6.25%` at `duty = 15`. See O-PWM-1 in
  `docs/uvm_plan/02_design_under_test.md` §1.
- **`&& duty` is redundant.** For any `THRESHOLD >= 0`, `duty > THRESHOLD` already implies
  `duty >= 1`. It is harmless, and it does not rescue a negative `THRESHOLD` either — that
  is still O-PWM-4, because the mixed-sign comparison is evaluated unsigned. Left in place
  as written.

**Every other file is unmodified from `01471d4`.**

## Checking for drift

From this directory:

```sh
SRC="/home/jonar/research_2026/enel441_453_lab/Rotating Disk/enel441_453_lab.srcs/sources_1/new"
for f in *.sv; do diff -q "$SRC/$f" "$f"; done
```

Expected output: differences in `controller.sv`, `prop_ctrl_pwm.sv` and `pwm_n_bit.sv`
only. Anything else means upstream moved and this copy needs a conscious re-sync decision.
