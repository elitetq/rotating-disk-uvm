// Uniform duty over the whole legal range: no inline constraint, only pwm_item's c_range.

class pwm_random_seq extends pwm_base_seq;
    `uvm_object_utils(pwm_random_seq)

    function new(string name = "pwm_random_seq");
        super.new(name);
    endfunction

    task body();
        if(!uvm_config_db#(int)::get(null,"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
        repeat(n_items) begin
            req = pwm_item::type_id::create("req");
            req.max_bits = bits;
            start_item(req);
            if (!req.randomize())
                `uvm_fatal("PWM_RANDOM_SEQ","Randomization failed.")
            finish_item(req);
        end
    endtask
endclass
