// Reset at random offsets within a period (R-PWM-5).
//   counter half: a_reset_clears in pwm_n_bit_sva (already bound, nothing to add here)
//   output half : watch_reset() below — pwm_out must be low on the first sampled cycle of reset
// Periods cut short by reset are flagged invalid by the monitor and skipped; the whole periods
// after each release are still checked by the scoreboard, which proves the DUT recovers.

class pwm_reset_test extends pwm_base_test;
    `uvm_component_utils(pwm_reset_test)

    virtual pwm_if vif;
    int n_resets, n_high;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        pwm_driver::type_id::set_type_override(pwm_ext_driver::get_type()); // before the agent builds its driver
        super.build_phase(phase);
        if(!uvm_config_db#(virtual pwm_if)::get(this,"","vif",vif))
            `uvm_fatal("NOCFG","vif could not be fetched from uvm db.");
    endfunction

    task run_phase(uvm_phase phase);
        pwm_reset_seq seq;
        fork
            watch_reset();
        join_none
        phase.raise_objection(this);          // "do not end the sim yet"
            seq = pwm_reset_seq::type_id::create("seq");
            seq.n_items = 20;
            seq.start(env.agent.sequencer);
        phase.drop_objection(this);           // "done"
    endtask

    protected task watch_reset();
        logic prev_reset;
        forever begin
            @(vif.mon_cb);
            if(vif.mon_cb.reset === 1'b1 && prev_reset !== 1'b1) begin // first sampled cycle of a reset pulse
                n_resets++;
                if(vif.mon_cb.pwm_out !== 1'b0) begin
                    n_high++;
                    `uvm_error("R-PWM-5",$sformatf("pwm_out = %b one cycle into reset (duty = %0d)", vif.mon_cb.pwm_out, vif.mon_cb.duty))
                end
            end
            prev_reset = vif.mon_cb.reset;
        end
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("RESET",$sformatf("%0d reset pulses checked, %0d with pwm_out high", n_resets, n_high),UVM_NONE)
    endfunction

endclass
