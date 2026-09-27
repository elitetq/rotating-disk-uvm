typedef enum { D_ZERO, D_ONE, D_DEADBAND, D_THR_P1, D_THR_P2, D_MID, D_MAX_M1, D_MAX } duty_class_e;

class pwm_coverage extends uvm_subscriber #(pwm_transaction);
    `uvm_component_utils(pwm_coverage)

    int bits, threshold;
    int n_sampled, n_skipped;

    duty_class_e duty_c;
    /*
        D_ZERO      - duty = 0
        D_ONE       - duty = 1
        D_DEADBAND  - duty = 2..threshold
        D_THR_P1    - duty = threshold+1
        D_THR_P2    - duty = threshold+2
        D_MID       - duty = threshold+3..max-2
        D_MAX_M1    - duty = max-1
        D_MAX       - duty = max (2**bits - 1)
    */

    covergroup cg_duty;
        option.per_instance = 1;

        cp_duty:        coverpoint duty_c;
    endgroup

    protected function duty_class_e classify_duty(int duty);
        if      (duty == 2**bits-1) return D_MAX;
        else    if(duty == 2**bits-2) return D_MAX_M1;
        else    if(duty == 0) return D_ZERO;
        else    if(duty == 1) return D_ONE;
        else    if(duty == threshold+1) return D_THR_P1;
        else    if(duty == threshold+2) return D_THR_P2;
        else    if(duty <= threshold) return D_DEADBAND;
        else    return D_MID;

    endfunction

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_duty = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(int)::get(this,"","BITS",bits))
            `uvm_fatal("NOCFG","Could not find bits configuration");
        if(!uvm_config_db#(int)::get(this,"","THRESHOLD",threshold))
            `uvm_fatal("NOCFG","Could not find threshold configuration");
        assert(bits > 3) else // if less than or equal to 3, chance of duty_class_e compression
            `uvm_error("ASTERR","bits assertion failed")
        assert(threshold+3 <= 2**bits-3) else // ensure duty_class_e can hit each enum
            `uvm_error("ASTERR","threshold assertion failed")
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COVERAGE",$sformatf("\n\nCoverage overall stats:\n\tSkipped: %0d\tSampled: %0d\tCoverage: %0d%%\n",n_skipped,n_sampled,cg_duty.get_inst_coverage()),UVM_NONE)
    endfunction

    virtual function void write(pwm_transaction pwmt);
        if(!pwmt.valid_period) begin n_skipped++; return; end // invalid period, ended early
        duty_c = classify_duty(pwmt.duty);
        cg_duty.sample();
        n_sampled++;
    endfunction

endclass