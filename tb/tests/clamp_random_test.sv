class clamp_random_test extends clamp_base_test;
    `uvm_component_utils(clamp_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction


    virtual task run_phase(uvm_phase phase);
        clamp_random_seq seq;
        phase.phase_done.set_drain_time(this, 50); // a few clocks so the monitor sees the last item
        phase.raise_objection(this);
            seq = clamp_random_seq::type_id::create("seq");
            seq.n_items = 50;
            seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
    // TODO: run_phase with its own sequence

endclass
