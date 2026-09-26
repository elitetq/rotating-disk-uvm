class pwm_smoke_test extends pwm_base_test;
    `uvm_component_utils(pwm_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        pwm_smoke_seq seq;
        phase.raise_objection(this);          // "do not end the sim yet"
            seq = pwm_smoke_seq::type_id::create("seq");
            seq.n_items = 50;
            seq.start(env.agent.sequencer);
        phase.drop_objection(this);           // "done"
    endtask



endclass