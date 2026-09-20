class pwm_transaction extends uvm_sequence_item;
    int unsigned duty; // Duty (nominally equal to high_cycles - 1)
    int unsigned high_cycles; // Total high cycles (always <= period_cycles)
    int unsigned period_cycles; // Total period cycles measured
    int unsigned valid_period; // Checks if duty was swapped mid-period

    `uvm_object_utils_begin(pwm_transaction)
        `uvm_field_int(duty, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(high_cycles, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(period_cycles, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(valid_period, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "pwm_transaction"); super.new(name); endfunction

endclass

class pwm_monitor extends uvm_monitor;
    `uvm_component_utils(pwm_monitor)

    virtual pwm_if  vif;
    int             bits;

    uvm_analysis_port#(pwm_transaction) ap;


    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ap = new("ap_monitor",this);

        if(!uvm_config_db#(virtual pwm_if)::get(null,"","vif",vif))
            `uvm_fatal(get_full_name(),"vif could not be resolved in monitor.");
        if(!uvm_config_db#(int)::get(null,"","BITS",bits))
            `uvm_fatal(get_full_name(),"bits could not be resolved in monitor.");
    endfunction

    virtual task run_phase(uvm_phase phase);
        pwm_transaction pwmt = pwm_transaction::type_id::create("pwmt");
        pwmt.high_cycles = 0;
        pwmt.period_cycles = 0;

        forever begin
            @(vif.mon_cb);

            if(vif.mon_cb.reset !== 0) begin // measuring
                if(pwmt.period_cycles) begin
                    pwmt.valid_period = 0;
                    ap.write(pwmt); // early reset condition, no period travelled
                    pwmt = pwm_transaction::type_id::create("pwmt");
                end
                pwmt.high_cycles = 0;
                pwmt.period_cycles = 0;
            end else begin // reset hit
                if(!pwmt.period_cycles) begin // one period sample
                    pwmt.duty = vif.mon_cb.duty & ((1 << bits) - 1);
                    pwmt.valid_period = 1;
                end else if(pwmt.duty != (vif.mon_cb.duty & (((1 << bits) - 1)))) begin // check for abrupt changes in duty, invalidate result
                    pwmt.valid_period = 0;
                end

                pwmt.high_cycles += vif.mon_cb.pwm_out;
                pwmt.period_cycles += 1;
                    
                if(pwmt.period_cycles == 2**bits) begin
                    ap.write(pwmt);
                    pwmt = pwm_transaction::type_id::create("pwmt");
                    pwmt.high_cycles = 0;
                    pwmt.period_cycles = 0;
                end
            end
        end
    endtask
endclass