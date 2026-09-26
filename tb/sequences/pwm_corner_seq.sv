// Directed walk over the duty corners (R-PWM-2,3,4,7). Corners are visited in order, so any
// n_items >= corners.size() hits every one at least once. hold_periods stays random.

class pwm_corner_seq extends pwm_base_seq;
    `uvm_object_utils(pwm_corner_seq)

    function new(string name = "pwm_corner_seq");
        super.new(name);
    endfunction

    task body();
        int unsigned corners[$];

        if(!uvm_config_db#(int)::get(null,"","BITS",bits)) `uvm_fatal("NOCFG","Bits could not be fetched from uvm db.");
        if(!uvm_config_db#(int)::get(null,"","THRESHOLD",threshold)) `uvm_fatal("NOCFG","Threshold could not be fetched from uvm db.");
        max_duty = (64'b1 << bits) - 1;

        corners = {0, 1, threshold, threshold+1, threshold+2, max_duty-1, max_duty};
        if (threshold > 0) corners.push_back(threshold-1); // T-1 only exists for T > 0

        for (int i = 0; i < n_items; i++) begin
            int unsigned corner_duty = corners[i % corners.size()];
            req = pwm_item::type_id::create("req");
            req.max_bits = bits;
            start_item(req);
            if (!req.randomize() with { duty == corner_duty; })
                `uvm_fatal("PWM_CORNER_SEQ","Randomization failed.")
            finish_item(req);
        end
    endtask
endclass
