# T3 — Phases and Objections

**Read before Phase A.** This tutorial explains the two failure modes every UVM beginner
hits: the simulation that ends instantly, and the one that never ends.

---

## Phases

Every UVM component inherits a set of methods called in a defined order across the whole
component tree. You override the ones you need.

| Phase | Direction | Time? | What goes here |
|---|---|:--:|---|
| `build_phase` | top-down | no | `create()` children, `config_db::get()` |
| `connect_phase` | bottom-up | no | connect TLM ports, sequencer to driver |
| `end_of_elaboration_phase` | bottom-up | no | `print_topology()`, final checks |
| `start_of_simulation_phase` | bottom-up | no | banners |
| **`run_phase`** | parallel | **yes** | everything that consumes simulation time |
| `extract` / `check` / `report_phase` | bottom-up | no | tally results, print summaries |

**Why top-down for build:** a parent must exist before it can create its children.
**Why bottom-up for connect:** children's ports must exist before a parent can wire them.

`run_phase` is the only one that can consume time, and it is a `task`. Everything else is a
`function` — put a `#10` in `build_phase` and it will not compile.

```systemverilog
class my_env extends uvm_env;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);          // NEVER omit this
    agent = my_agent::type_id::create("agent", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.ap.connect(sb.ap_imp);
  endfunction
endclass
```

Omitting `super.build_phase(phase)` skips the base class's work — including automatic
configuration application — and produces failures that look like anything but a missing
`super` call.

---

## Objections: how the simulation knows when to stop

`run_phase` runs in **parallel** across every component. Some of them (drivers, monitors) are
`forever` loops that never return. So how does the simulation end?

**Objections.** Each is a vote for "keep going". When the count reaches zero, the run phase
ends.

```systemverilog
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);       // "I have work to do"
    seq.start(env.agent.sequencer);
    #100ns;                            // drain
    phase.drop_objection(this);        // "done"
  endtask
```

### Failure mode 1 — the instant pass

```
UVM_INFO @ 0: reporter [RNTST] Running test my_test...
--- UVM Report Summary ---
UVM_ERROR : 0
```

Simulation time never advanced. **No objection was raised**, so the run phase ended
immediately with nothing driven and nothing checked — and it reports a clean pass.

This is the most dangerous outcome in UVM, because it looks exactly like success. Two habits
that catch it:

- Check that the report summary shows a non-zero end time.
- Make every scoreboard raise a `uvm_error` in `report_phase` if it checked zero
  transactions. This guide asks you to do that in every phase, and this is why.

### Failure mode 2 — the hang

The simulation runs forever. **An objection was raised and never dropped** — usually an early
return, an exception path, or a `drop` inside a branch that did not execute.

Add a global timeout so a hang fails loudly instead of eating your afternoon:

```systemverilog
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(1ms, 0);
  endfunction
```

### Who should raise objections

**Only the test**, in this project. Drivers and monitors should not — they are `forever`
loops and would never drop.

The nuance worth knowing: objections cost simulation performance if raised per-transaction,
which is why large environments raise once per test and use other mechanisms (sequence
completion, drain time) for finer control. At this scale, one raise/drop pair per test is
correct and simple.

### Drain time

```systemverilog
    seq.start(env.agent.sequencer);
    // the last item is driven, but the monitor has not observed it yet
    repeat (10) @(vif.mon_cb);      // let it drain
    phase.drop_objection(this);
```

`seq.start()` returns when the last item has been handed to the driver — **not** when the DUT
has responded and the monitor has published. Drop the objection too early and you silently
lose the final check. Symptom: the scoreboard checks N−1 transactions when you sent N.

`phase.phase_done.set_drain_time(this, 100ns)` does the same thing declaratively.

---

## Micro-exercise (20 minutes)

Take the `tb_hello.sv` smoke test from `01_toolchain.md` and:

1. Comment out `raise_objection`. Run. Note the end time and that it still "passes".
2. Restore it, comment out `drop_objection`. Run. Watch it hang; kill it.
3. Restore both, add `uvm_top.set_timeout(1us, 0)` and remove the drop again. Watch it fail
   with a timeout instead of hanging.

Ten minutes, and you will recognize both symptoms instantly for the rest of the project.

---

## Further reading

- UVM 1.2 User's Guide, ch. 4 (phasing)
- Verification Academy — UVM Phasing cookbook page
- Doulos UVM Golden Reference — the phase table is worth printing
