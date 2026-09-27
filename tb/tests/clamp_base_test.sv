class clamp_base_test extends uvm_test;
  `uvm_component_utils(clamp_base_test)

  clamp_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    int n;
    super.build_phase(phase);
    $value$plusargs("UVM_MAX_QUIT_COUNT=%d",n);
    uvm_report_server::get_server().set_max_quit_count(n);
    env = clamp_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    clamp_base_seq seq;
    phase.phase_done.set_drain_time(this, 50); // a few clocks so the monitor sees the last item
    phase.raise_objection(this);
        seq = clamp_base_seq::type_id::create("seq");
        seq.n_items = 50;
        seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask

endclass
