// The workhorse: 50 items, uniform duty (R-PWM-1,2). Checked by the scoreboard and SVA.

class pwm_random_test extends pwm_base_test;
    `uvm_component_utils(pwm_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        pwm_random_seq seq;
        phase.raise_objection(this);          // "do not end the sim yet"
            seq = pwm_random_seq::type_id::create("seq");
            seq.n_items = 50;
            seq.start(env.agent.sequencer);
        phase.drop_objection(this);           // "done"
    endtask

endclass
