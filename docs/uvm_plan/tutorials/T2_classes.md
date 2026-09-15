# T2 — The 15% of SystemVerilog OOP That UVM Needs

**Read before Phase A** if you have not written classes in SystemVerilog.

You do not need to become an object-oriented programmer. UVM uses a small, repetitive subset,
and this covers it.

---

## Why classes at all

Modules are static: fixed at elaboration, permanent, no dynamic creation. That is right for
hardware and wrong for stimulus.

Verification needs objects that are **created on demand** (a thousand transactions, then
gone), **randomized**, **substitutable** (an error-injecting driver in place of a normal one),
and **passed by handle**. Those are class features. That is the whole justification — nothing
more ideological than that.

---

## The pieces, in the order you will meet them

### Declaring and constructing

```systemverilog
class pwm_item;
  int duty;

  function new(int d = 0);      // the constructor is always called `new`
    duty = d;
  endfunction

  function void print_me();
    $display("duty = %0d", duty);
  endfunction
endclass

pwm_item a;                     // a HANDLE, currently null
a = new(42);                    // now it points to an object
a.print_me();
```

**Handles, not values.** `pwm_item b = a;` gives two handles to the *same* object.
`b.duty = 7` changes what `a` sees. This is the number-one source of confusion coming from
Verilog. Use `copy()` (which the UVM field macros generate for you) when you want a distinct
object.

### Inheritance

```systemverilog
class pwm_corner_item extends pwm_item;
  function new(int d = 0);
    super.new(d);               // ALWAYS call the parent constructor first
  endfunction
endclass
```

`super.` reaches the parent's version of a method. Forgetting `super.new()` is a common
compile error; forgetting `super.build_phase(phase)` in a UVM component is a common *silent*
error.

### Virtual methods and polymorphism

```systemverilog
class base;
  virtual function void go(); $display("base"); endfunction
endclass

class derived extends base;
  virtual function void go(); $display("derived"); endfunction
endclass

base h = derived::type_id::create("h");
h.go();      // prints "derived" — the OBJECT's type decides, not the handle's
```

That is the entire mechanism behind the UVM factory. Non-`virtual` and the handle's type
decides, which is almost never what you want. **In UVM, methods you override are already
virtual in the base class** — you rarely declare it yourself.

### `$cast`

Going from a base handle to a derived one is checked at run time:

```systemverilog
base b = get_something();
derived d;
if (!$cast(d, b))
  `uvm_error("CAST", "not a derived object")
```

You will meet this in monitors and scoreboards that receive `uvm_sequence_item` handles.

### Parameterized classes

```systemverilog
class fifo #(type T = int);
  T items[$];
endclass

fifo #(pwm_item) my_fifo = new();
```

You will *use* these constantly — `uvm_driver #(pwm_item)`,
`uvm_analysis_port #(pwm_obs)` — and rarely write one.

---

## The UVM-specific layer

### Registration macros

```systemverilog
class pwm_item extends uvm_sequence_item;
  rand bit [7:0] duty;

  `uvm_object_utils_begin(pwm_item)
    `uvm_field_int(duty, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pwm_item");
    super.new(name);
  endfunction
endclass
```

`` `uvm_object_utils_begin/end `` registers the type with the factory and **generates
`print()`, `copy()`, `compare()`, `pack()` and `record()`** from the field list. That
generation is the reason your class code stays short — hand-writing those five methods for
every transaction is exactly the OOP busywork you are avoiding.

For components (things that live for the whole simulation) the equivalent is
`` `uvm_component_utils(my_driver) ``, and the constructor signature is different:

```systemverilog
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
```

**Objects** (transactions, sequences) take `(string name)`. **Components** (drivers,
monitors, envs) take `(string name, uvm_component parent)` and form a permanent tree.

### `create` instead of `new`

```systemverilog
  driver = pwm_driver::type_id::create("driver", this);   // do this
  driver = new("driver", this);                           // not this
```

`create` asks the factory, which allows substitution later. `new` hardcodes the type. See
`T5`.

---

## The five mistakes everyone makes

1. **Forgetting `super.new()`** — compile error, easy.
2. **Forgetting `super.build_phase(phase)`** — silent, and things mysteriously do not exist.
3. **Assuming assignment copies** — two handles, one object.
4. **Using `new()` instead of `type_id::create()`** — works, until you want an override.
5. **Null handle dereference** — `Fatal: null object access`. You declared a handle and never
   constructed it. In UVM this usually means a `build_phase` create is missing.

---

## Micro-exercise (30 minutes)

Write a `packet` class with `rand bit [7:0] addr, data`, register it with the field macros,
then in an `initial` block: create five, randomize each, print each, copy one into a second
handle, modify the copy, and print both to confirm they are independent. Then assign a handle
directly (`p2 = p1`), modify, and print both to see the difference.

Fifteen lines. It makes handles-versus-values permanent.

---

## Further reading

- IEEE 1800-2017 §8 (classes)
- ChipVerify — SystemVerilog OOP section
- Doulos — UVM Golden Reference Guide (worth owning; the macro reference alone earns it)
- Spear & Tumbush, *SystemVerilog for Verification*, ch. 5 & 8
