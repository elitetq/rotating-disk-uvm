
// only task is to hand pwm_items to driver or other related functions

class pwm_base_seq extends uvm_sequence #(pwm_item);
  `uvm_object_utils(pwm_base_seq) // objects are easily mutable (copy-able) and good for mass exchanges of differnet classes (items!)

  int unsigned n_items = 20;
  int unsigned bits;

  function new(string name = "pwm_base_seq");
    super.new(name);
  endfunction

  task body();
    if(!uvm_config_db#(int)::get(get_sequencer(),"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
    repeat(n_items) begin
      req = pwm_item::type_id::create("req");
      req.max_bits = bits;
      start_item(req);
      if (!req.randomize()) `uvm_fatal("PWM_BASE_SEQ","Randomization failed.")
      finish_item(req);
    end
  endtask
endclass
