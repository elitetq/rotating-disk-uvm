// pwm_item plus the timing knobs pwm_ext_driver needs. The soft defaults reproduce plain
// pwm_item behaviour exactly: duty lands on the period boundary and no reset is pulsed.

class pwm_ext_item extends pwm_item;

  rand int unsigned offset_cycles;   // cycles into the first period before duty is applied
  rand bit          do_reset;        // pulse reset during this item
  rand int unsigned reset_at;        // cycles after duty is applied before reset asserts
  rand int unsigned reset_cycles;    // how many cycles reset is held

  `uvm_object_utils_begin(pwm_ext_item)
    `uvm_field_int(offset_cycles, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(do_reset,      UVM_ALL_ON | UVM_BIN)
    `uvm_field_int(reset_at,      UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(reset_cycles,  UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pwm_ext_item");
    super.new(name);
  endfunction

  constraint c_offset {
    soft offset_cycles == 0;
    offset_cycles < (64'b1 << max_bits);   // stays inside the first period
  }

  constraint c_reset {
    soft do_reset == 0;
    reset_at < (64'b1 << max_bits);        // lands inside the first period
    soft reset_cycles inside {[1:4]};
  }

endclass
