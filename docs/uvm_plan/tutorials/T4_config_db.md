# T4 — `uvm_config_db` and Virtual Interfaces

**Read before Phase A.** This is how a class gets hold of a wire.

---

## The problem

A driver needs to wiggle pins. Pins live in an `interface` instance in the module hierarchy.
Classes have no place in that hierarchy and cannot write `tb_top.vif.duty`.

So the handle must be *passed in* from somewhere that can see the hierarchy — the testbench
top — down to a component that was not even constructed yet when the top ran.

`uvm_config_db` is that channel: a hierarchical key-value store, written before components
are built and read during `build_phase`.

---

## The two halves

**Set**, from the testbench top:

```systemverilog
module tb_pwm_top;
  pwm_if vif (.clk(clk));

  initial begin
    uvm_config_db#(virtual pwm_if)::set(null, "*", "vif", vif);
    //                              ^^^^  ^^^   ^^^^^  ^^^
    //                              cntxt scope  key   value
    run_test();
  end
endmodule
```

**Get**, in a component's `build_phase`:

```systemverilog
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pwm_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"virtual interface not set for ", get_full_name()})
  endfunction
```

**Always check the return value and `uvm_fatal` on failure.** The alternative is a null
handle and a crash five hundred lines later with no clue where it came from. Include
`get_full_name()` in the message — it tells you exactly which instance could not find its
configuration.

---

## Scope matching

`set(context, scope, key, value)` — the *effective path* is `context`'s full name plus
`scope`. `get(context, scope, key, var)` matches against the getter's full instance path.

```systemverilog
// From a module (no context): scope is an absolute path with wildcards.
uvm_config_db#(virtual quad_if)::set(null, "*",            "vif", quad_vif);
uvm_config_db#(virtual quad_if)::set(null, "uvm_test_top.env.quad*", "vif", quad_vif);

// From a component: context is `this`, so the scope is relative.
uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
```

Typical instance paths look like:

```
uvm_test_top
uvm_test_top.env
uvm_test_top.env.quad
uvm_test_top.env.quad.driver
```

`uvm_top.print_topology()` in `end_of_elaboration_phase` prints the whole tree. Call it once
per phase while developing — it is the fastest way to see what your scope strings actually
have to match.

---

## Five ways this bites you

**1. Type mismatch.** The type parameter must match *exactly*.

```systemverilog
uvm_config_db#(virtual pwm_if)::set(...);        // set
uvm_config_db#(virtual pwm_if.DRV)::get(...);    // get — DIFFERENT TYPE, silently fails
```

Same for `int` vs `int unsigned` vs `bit [31:0]`. There is no coercion, and no diagnostic
beyond `get` returning 0.

**2. `"*"` is too broad once you have two agents of the same type.** Both get the same
interface, both drive the same pins, and the symptom looks like a DUT bug. Scope precisely
from the start:

```systemverilog
uvm_config_db#(virtual quad_if)::set(null, "*.quad_a*", "vif", vif_a);
uvm_config_db#(virtual quad_if)::set(null, "*.quad_b*", "vif", vif_b);
```

**3. Setting after the component was built.** `set` from a testbench `initial` block runs
before `run_test()`, which is correct. `set` inside a component's `build_phase` only reaches
components built *later* — i.e. its own descendants, because build is top-down. Setting for a
sibling or a parent does nothing.

**4. Getting outside `build_phase`.** Legal, but by `run_phase` the value may have been
overwritten. Get in `build_phase`, store in a field.

**5. Wildcards are not regex.** `*` matches any sequence, `?` a single character. `.` is a
literal separator, not "any character".

---

## What else belongs in the config_db

Anything a component needs that varies per test:

```systemverilog
uvm_config_db#(int)::set(null, "*", "BITS",      BITS);
uvm_config_db#(int)::set(null, "*", "THRESHOLD", THRESHOLD);
uvm_config_db#(uvm_active_passive_enum)::set(this, "pwm", "is_active", UVM_PASSIVE);
```

### Scaling up: the config object

Once a component needs five settings, bundle them:

```systemverilog
class pwm_config extends uvm_object;
  `uvm_object_utils(pwm_config)
  int  bits      = 8;
  int  threshold = 14;
  bit  checks_enabled = 1;
  virtual pwm_if vif;
  function new(string name = "pwm_config"); super.new(name); endfunction
endclass
```

One `set`, one `get`, and adding a knob touches one file. Worth doing at Phase D when you
have three agents; overkill at Phase A. Building it when the pain appears — rather than
up front — is the right call, and being able to say *why* you introduced it is better than
having had it from the start.

---

## Micro-exercise (15 minutes)

In `tb_hello.sv`:

1. `set` an `int` called `"my_value"` from the module, and `get` it in the test. Print it.
2. Change the `get` to `uvm_config_db#(int unsigned)`. Watch it fail. Note that the only
   diagnostic is your own `uvm_fatal`.
3. Change the `set` scope from `"*"` to `"nonexistent.*"`. Watch it fail the same way.
4. Add `uvm_top.print_topology()` and read the instance paths.

---

## Further reading

- UVM 1.2 User's Guide, ch. 6 (configuration)
- Verification Academy — UVM Config DB cookbook
- ChipVerify — UVM Config DB
