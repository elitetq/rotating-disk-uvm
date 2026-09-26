class pwm_base_test extends uvm_test;
  `uvm_component_utils(pwm_base_test)

  pwm_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = pwm_env::type_id::create("env", this);
  endfunction

  // Useful and cheap: dump the whole component tree once, so you can see the
  // instance paths your config_db calls need to match.
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    pwm_base_seq seq;
    phase.phase_done.set_drain_time(this,4*(64'b1 << env.agent.driver.bits)); // hold for 4 pwm periods after last item
    phase.raise_objection(this);          // "do not end the sim yet"
        seq = pwm_base_seq::type_id::create("seq");
        seq.n_items = 50;
        seq.start(env.agent.sequencer);
    phase.drop_objection(this);           // "done"
  endtask

endclass
