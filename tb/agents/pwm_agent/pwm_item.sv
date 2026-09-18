// sequence transactions

`include "uvm_macros.svh"

class pwm_item extends uvm_sequence_item;

  rand bit [31:0] duty;
  rand int unsigned hold_periods;    // how many full PWM periods to hold this duty
  int max_bits;                      // how many bits to clamp the duty inside

  // Field macros give you print / copy / compare / pack for free.
  // Writing those methods by hand is exactly the OOP busywork we are avoiding.
  `uvm_object_utils_begin(pwm_item)
    `uvm_field_int(duty,         UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(hold_periods, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pwm_item");
    super.new(name);
  endfunction

  function void pre_randomize(); // called just before .randomize()
    assert(64'(2**max_bits-1) > 0);
  endfunction

  constraint c_hold {
    hold_periods inside {[1:3]};
  }

  constraint c_range {
    duty inside {[0:64'(2**max_bits-1)]};
  }
  

endclass