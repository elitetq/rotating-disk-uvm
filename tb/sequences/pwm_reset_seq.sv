// Every item pulses reset at a random point inside its first period (R-PWM-5). Half the duties
// sit in the deadband and half above it, so reset is hit with pwm_out both idle and active.
// Needs pwm_ext_driver.

class pwm_reset_seq extends pwm_base_seq;
    `uvm_object_utils(pwm_reset_seq)

    function new(string name = "pwm_reset_seq");
        super.new(name);
    endfunction

    task body();
        pwm_ext_item item;

        if(!uvm_config_db#(int)::get(null,"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
        if(!uvm_config_db#(int)::get(null,"","THRESHOLD",threshold)) `uvm_fatal("NOCFG","Threshold could not be fetched from uvm db.");
        max_duty = (64'b1 << bits) - 1;
        repeat(n_items) begin
            item = pwm_ext_item::type_id::create("req");
            item.max_bits = bits;
            start_item(item);
            if (!item.randomize() with {
                do_reset == 1;
                duty dist {
                    [0:threshold]          :/ 1,
                    [threshold+1:max_duty] :/ 1
                };
            })
                `uvm_fatal("PWM_RESET_SEQ","Randomization failed.")
            finish_item(item);
        end
    endtask
endclass
