
// only task is to hand pwm_items to driver or other related functions

class pwm_base_seq extends uvm_sequence #(pwm_item);
  `uvm_object_utils(pwm_base_seq) // objects are easily mutable (copy-able) and good for mass exchanges of differnet classes (items!)

  int n_items = 20;
  int bits;
  int threshold;
  int max_duty;

  function new(string name = "pwm_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    if(!uvm_config_db#(int)::get(null,"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
    if(!uvm_config_db#(int)::get(null,"","THRESHOLD",threshold)) `uvm_fatal("NOCFG","Threshold could not be fetched from uvm db.");
    max_duty = (64'b1 << bits) - 1;
    repeat(n_items) begin
      req = pwm_item::type_id::create("req");
      req.max_bits = bits;
      start_item(req);
      if (!req.randomize() with { // inline constraints
        duty dist {
          [0:1] := 10,
          [2:threshold-1] :/ 20,
          [threshold:threshold+2] := 10,
          [threshold+3:max_duty-2] :/ 20,
          [max_duty-1:max_duty] := 10

        };
      })
        `uvm_fatal("PWM_BASE_SEQ","Randomization failed.")
      finish_item(req);
    end
  endtask
endclass
