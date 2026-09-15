# T6 — TLM: Analysis Ports and the Sequencer Handshake

**Read before Phase A.** Two mechanisms: how monitors broadcast, and how drivers get work.

---

## Part 1: Analysis ports (broadcast, one-to-many)

A monitor observes something. Who needs to know? A scoreboard. A coverage collector. Maybe a
logger. Possibly nothing, if the agent is running purely for waveform inspection.

The monitor should not have to know:

```systemverilog
class pwm_monitor extends uvm_monitor;
  uvm_analysis_port #(pwm_obs) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      // ... observe ...
      ap.write(obs);        // to nobody, or to five subscribers. Same code.
    end
  endtask
endclass
```

Consumers implement `write()`:

```systemverilog
class pwm_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp #(pwm_obs, pwm_scoreboard) ap_imp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_imp = new("ap_imp", this);
  endfunction

  function void write(pwm_obs obs);      // called automatically
    // check it
  endfunction
endclass
```

Wired in `connect_phase`:

```systemverilog
  monitor.ap.connect(sb.ap_imp);
  monitor.ap.connect(cov.analysis_export);
```

`ap.write()` calls every connected `write()` in turn, synchronously, in the caller's process.
It is a function, not a task — **it cannot consume time**. A subscriber that needs to block
must queue the transaction and process it in its own `run_phase`.

### The three port kinds

| | Role |
|---|---|
| `uvm_analysis_port` | Produces. Has `write()`, which fans out. |
| `uvm_analysis_imp` | Consumes. *You* implement `write()`. |
| `uvm_analysis_export` | Forwards. Passes a child's imp up the hierarchy without implementing anything. |

An agent typically declares an `export` (or its own `port`) so the environment connects to
the agent, not into its internals. That keeps the agent's structure private.

### Two streams into one scoreboard

`write()` can only be defined once per class. For a scoreboard receiving two different
transaction types:

```systemverilog
`uvm_analysis_imp_decl(_quad)
`uvm_analysis_imp_decl(_ctrl)

class ctrl_predictor extends uvm_component;
  uvm_analysis_imp_quad #(quad_obs, ctrl_predictor) quad_imp;
  uvm_analysis_imp_ctrl #(ctrl_obs, ctrl_predictor) ctrl_imp;

  function void write_quad(quad_obs obs); ... endfunction
  function void write_ctrl(ctrl_obs obs); ... endfunction
endclass
```

The macro generates a suffixed imp class that calls `write_<suffix>` instead of `write`.
Declare it at package scope, outside any class. You need this at Phase D.

### `uvm_subscriber`

A convenience base that is just a component with a built-in `analysis_export` and a pure
virtual `write()`. Ideal for coverage collectors:

```systemverilog
class pwm_coverage extends uvm_subscriber #(pwm_obs);
  function void write(pwm_obs t);
    obs = t;
    cg.sample();
  endfunction
endclass
```

---

## Part 2: The sequencer handshake (point-to-point, blocking)

Different mechanism, different purpose. Analysis ports broadcast observations; the sequencer
port delivers work, one item at a time, with backpressure.

**Driver side:**

```systemverilog
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);   // blocks until an item is available
      drive(req);                         // takes simulation time
      seq_item_port.item_done();          // releases the sequencer
    end
  endtask
```

**Sequence side:**

```systemverilog
  task body();
    repeat (20) begin
      req = pwm_item::type_id::create("req");
      start_item(req);                    // blocks until the driver is ready
      if (!req.randomize()) `uvm_error("RAND", "failed")
      finish_item(req);                   // blocks until item_done()
    end
  endtask
```

**Connected once:**

```systemverilog
  driver.seq_item_port.connect(sequencer.seq_item_export);
```

### Why randomize *between* `start_item` and `finish_item`

`start_item` returns when the driver is ready — which is *now*, in simulation time.
Randomizing at that moment means constraints can react to what has already happened
(current DUT state, a value the monitor just published). Randomizing earlier fixes the
stimulus before you know the context.

For simple stimulus it makes no difference. It is still the idiom, and it costs nothing.

### `item_done()` and backpressure

The sequence blocks in `finish_item` until the driver calls `item_done()`. That is what stops
a sequence from generating ten thousand items instantly while the driver is still on the
first. The handshake *is* the flow control.

---

## Comparison

| | Analysis port | Sequencer port |
|---|---|---|
| Direction | monitor → consumers | sequence → driver |
| Cardinality | one-to-many (or zero) | one-to-one |
| Blocking | no — `write()` is a function | yes — both sides block |
| Purpose | observations | work |

---

## Micro-exercise (30 minutes)

1. Add a second subscriber to your Phase A monitor's port that just counts transactions.
   Confirm the scoreboard and the counter both receive every one, without touching the
   monitor.
2. Disconnect the scoreboard entirely. Confirm the monitor still runs and the counter still
   counts. That decoupling is the whole point.
3. Add a `#100ns` delay inside the driver's `drive()` task. Watch the sequence slow down to
   match — the backpressure is real, not theoretical.

---

## Further reading

- UVM 1.2 User's Guide, ch. 7 (TLM)
- Verification Academy — UVM Analysis Port / Sequencer cookbook pages
- ChipVerify — UVM TLM section
