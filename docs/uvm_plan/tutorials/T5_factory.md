# T5 — The Factory

**Read before Phase A**, though its value only becomes obvious later — and it is fine to
conclude it does not earn its keep in an environment this small, as long as you can say why.

---

## What it is

Instead of constructing an object directly:

```systemverilog
  driver = new("driver", this);                            // hardcodes the type
```

you ask a registry:

```systemverilog
  driver = pwm_driver::type_id::create("driver", this);    // asks the factory
```

The factory looks up what `pwm_driver` should currently resolve to, and returns *that*. By
default it is `pwm_driver`. But someone else can change the answer without touching this
line.

---

## Why that matters

```systemverilog
class pwm_error_driver extends pwm_driver;
  `uvm_component_utils(pwm_error_driver)
  // ... occasionally corrupts the duty value ...
endclass

class pwm_error_test extends pwm_base_test;
  function void build_phase(uvm_phase phase);
    set_type_override_by_type(pwm_driver::get_type(), pwm_error_driver::get_type());
    super.build_phase(phase);      // MUST come after the override
  endfunction
endclass
```

The environment, the agent and the driver instantiation are all unchanged. The test swaps in
a different driver from outside.

Without the factory you would have to modify the agent — a component you had already declared
finished and verified — to add an if-statement for a case it should not know about.

**Registration** is what makes a type visible to the factory. That is what
`` `uvm_component_utils `` and `` `uvm_object_utils `` do, alongside generating the field
methods.

---

## Two kinds of override

```systemverilog
// Every pwm_driver anywhere becomes pwm_error_driver:
set_type_override_by_type(pwm_driver::get_type(), pwm_error_driver::get_type());

// Only the one at this instance path:
set_inst_override_by_type("uvm_test_top.env.agent.driver",
                          pwm_driver::get_type(), pwm_error_driver::get_type());
```

Instance overrides are what you want with several agents of the same type.

---

## Rules that will bite you

**1. Override before `super.build_phase()`.** Build is top-down; once a component is
constructed the override is too late.

**2. The override type must extend the original.** `pwm_error_driver extends pwm_driver`.
Otherwise the handle assignment fails at run time.

**3. `create()` everywhere, or the override does nothing.** One stray `new()` and that
component silently ignores every override. This is why the guide uses `type_id::create()`
even in Phase A where nothing is overridden — the habit has to be total to be useful.

**4. Objects and components have different create signatures.**

```systemverilog
  item = pwm_item::type_id::create("item");                 // uvm_object
  drv  = pwm_driver::type_id::create("driver", this);       // uvm_component
```

**5. `print_factory()` when confused.**

```systemverilog
  factory.print();     // in end_of_elaboration_phase
```

Lists every registered type and every active override. It answers "why did my override not
take effect" in about ten seconds.

---

## Sequences use it too

```systemverilog
  req = pwm_item::type_id::create("req");
  start_item(req);
  if (!req.randomize()) `uvm_error("RAND", "randomize failed")
  finish_item(req);
```

Creating items through the factory means a test can substitute a constrained subclass
globally — a common and clean way to change stimulus character without editing sequences.

---

## An honest assessment for this project

In an environment with one driver per agent and no third-party VIP, you may never write an
override. That is a normal outcome, and "I used `type_id::create` throughout so overrides are
available, but the environment was small enough that `config_db` knobs covered every variation
I needed" is a *better* interview answer than an override invented to have one.

If you want one real use, the error-injecting driver above is worth twenty minutes: it gives
you a `pwm_error_test` that proves your scoreboard catches corrupted stimulus, which is a
genuine result and not just a demonstration.

---

## Micro-exercise (25 minutes)

1. Add `factory.print()` to `end_of_elaboration_phase` in your Phase A test. Read the output.
2. Write `pwm_error_driver` that inverts `duty` on every fifth item.
3. Write `pwm_error_test` that overrides it.
4. Run. Confirm the scoreboard fails — and that it names the right instance.
5. Move `set_type_override_by_type` to *after* `super.build_phase(phase)` and confirm the
   override silently stops working.

Step 5 is the one you will remember.

---

## Further reading

- UVM 1.2 User's Guide, ch. 5 (factory)
- Verification Academy — UVM Factory cookbook
- Doulos UVM Golden Reference — override syntax summary
