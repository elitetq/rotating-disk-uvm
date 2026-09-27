// Directed duty corners (R-PWM-2,3,4,7): 0, 1, T-1, T, T+1, T+2, max-1, max, two passes.
// duty = max must give high_cycles == 2**BITS (R-PWM-4); the scoreboard already expects that.

class pwm_corner_test extends pwm_base_test;
    `uvm_component_utils(pwm_corner_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        pwm_corner_seq seq;
    phase.phase_done.set_drain_time(this,4*(64'b1 << env.agent.driver.bits)); // hold for 4 pwm periods after last item
        phase.raise_objection(this);          // "do not end the sim yet"
            seq = pwm_corner_seq::type_id::create("seq");
            seq.n_items = 16;
            seq.start(env.agent.sequencer);
        phase.drop_objection(this);           // "done"
    endtask

endclass
