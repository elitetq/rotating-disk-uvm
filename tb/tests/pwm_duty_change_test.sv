// OBSERVATION test, not a checking test (O-PWM-5). duty switches mid-period, so the monitor
// flags that period invalid and the scoreboard skips it; the steady periods around it are still
// checked. pwm_change_observer prints what each mixed period actually produced, for
// docs/results.md. Pair each O-PWM-5 line with the DRIVER line before it for the offset.

class pwm_change_observer extends uvm_subscriber #(pwm_transaction);
    `uvm_component_utils(pwm_change_observer)

    int threshold;
    protected pwm_transaction pending; // last mixed period, waiting on the next one for the new duty

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(int)::get(this,"","THRESHOLD",threshold))
            `uvm_fatal("NOCFG","Could not find threshold configuration");
    endfunction

    // A mixed period's duty is the old one (sampled at its start); the next period's duty is the new one.
    virtual function void write(pwm_transaction pwmt);
        if(pending != null) begin
            `uvm_info("O-PWM-5",$sformatf("duty %0d -> %0d mid-period: high_cycles = %0d (steady old = %0d, steady new = %0d)",
                pending.duty, pwmt.duty, pending.high_cycles,
                dut_pkg::expected_pwm_high(pending.duty, threshold),
                dut_pkg::expected_pwm_high(pwmt.duty, threshold)),UVM_LOW)
            pending = null;
        end
        if(!pwmt.valid_period) pending = pwmt;
    endfunction

endclass

class pwm_duty_change_test extends pwm_base_test;
    `uvm_component_utils(pwm_duty_change_test)

    pwm_change_observer observer;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        pwm_driver::type_id::set_type_override(pwm_ext_driver::get_type()); // before the agent builds its driver
        super.build_phase(phase);
        observer = pwm_change_observer::type_id::create("observer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        env.agent.ap.connect(observer.analysis_export);
    endfunction

    task run_phase(uvm_phase phase);
        pwm_duty_change_seq seq;
        phase.phase_done.set_drain_time(this,4*2**env.agent.driver.bits); // hold for 4 pwm periods after last item
        phase.raise_objection(this);          // "do not end the sim yet"
            seq = pwm_duty_change_seq::type_id::create("seq");
            seq.n_items = 20;
            seq.start(env.agent.sequencer);
        phase.drop_objection(this);           // "done"
    endtask

endclass
