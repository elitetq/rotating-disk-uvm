// only task is to hand pwm_items to driver or other related functions

class pwm_smoke_seq extends pwm_base_seq;
    `uvm_object_utils(pwm_smoke_seq)

    function new(string name = "pwm_smoke_seq");
        super.new(name);
    endfunction

    task body();
        if(!uvm_config_db#(int)::get(null,"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
        if(!uvm_config_db#(int)::get(null,"","THRESHOLD",threshold)) `uvm_fatal("NOCFG","Threshold could not be fetched from uvm db.");
        max_duty = (64'b1 << bits) - 1;
        repeat(n_items) begin
        req = pwm_item::type_id::create("req");
        req.max_bits = bits;
        start_item(req);
        if (!req.randomize() with { // inline constraints
            duty dist {
                [1:2] := 10,
                [threshold:threshold+3] := 10,
                [2**max_bits-2:2**max_bits-1] := 10
            };
        })
            `uvm_fatal("PWM_SMOKE_SEQ","Randomization failed.")
        finish_item(req);
        end
    endtask
endclass
