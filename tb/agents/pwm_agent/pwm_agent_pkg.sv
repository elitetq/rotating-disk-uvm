class pwm_item extends uvm_sequence_item;

  rand bit [15:0] duty;
  rand int unsigned hold_periods;    // how many full PWM periods to hold this duty

  // Field macros give you print / copy / compare / pack for free.
  // Writing those methods by hand is exactly the OOP busywork we are avoiding.
  `uvm_object_utils_begin(pwm_item)
    `uvm_field_int(duty,         UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(hold_periods, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pwm_item");
    super.new(name);
  endfunction

  // TODO(you): constrain hold_periods to something sane — 1 to 3.
  //            A test that holds each duty for 200 periods is a slow test that
  //            checks nothing extra.
  constraint c_hold { }

  // TODO(you): constrain duty to the legal range for the configured width.
  //            Problem: this class does not know BITS. Two options —
  //              (a) a non-rand `int max_duty` field the sequence sets before
  //                  randomize(), with `constraint c_range { duty <= max_duty; }`
  //              (b) an inline constraint at the call site:
  //                  `item.randomize() with { duty <= (1<<bits)-1; }`
  //            Pick one and write down why. (a) keeps the knowledge in the item;
  //            (b) keeps the item dumb. Both are defensible; (a) scales better.
  constraint c_range { }

endclass
