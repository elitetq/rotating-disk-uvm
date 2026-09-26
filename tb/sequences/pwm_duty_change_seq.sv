// Every item switches duty offset_cycles into a period instead of on the boundary (O-PWM-5).
// offset is 1..max_duty, so the switch is always strictly mid-period. Needs pwm_ext_driver.

class pwm_duty_change_seq extends pwm_base_seq;
    `uvm_object_utils(pwm_duty_change_seq)

    function new(string name = "pwm_duty_change_seq");
        super.new(name);
    endfunction

    task body();
        pwm_ext_item item;

        if(!uvm_config_db#(int)::get(null,"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
        max_duty = (64'b1 << bits) - 1;
        repeat(n_items) begin
            item = pwm_ext_item::type_id::create("req");
            item.max_bits = bits;
            start_item(item);
            if (!item.randomize() with { offset_cycles inside {[1:max_duty]}; })
                `uvm_fatal("PWM_DUTY_CHANGE_SEQ","Randomization failed.")
            finish_item(item);
        end
    endtask
endclass
