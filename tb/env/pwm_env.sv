class pwm_env extends uvm_env;

    `uvm_component_utils(pwm_env)
    pwm_scoreboard scoreboard;
    pwm_coverage coverage;
    pwm_agent agent;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.ap.connect(scoreboard.analysis_export);
        agent.ap.connect(coverage.analysis_export);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE); // set active state so pwm_agent instantiates driver and sequencer. Note that it is scoped to "agent" which is important because our agent is also called "agent", otherwise it wont be able to read is_active
        agent = pwm_agent::type_id::create("agent",this);
        scoreboard = pwm_scoreboard::type_id::create("scoreboard",this);
        coverage = pwm_coverage::type_id::create("coverage",this);
    endfunction

endclass
