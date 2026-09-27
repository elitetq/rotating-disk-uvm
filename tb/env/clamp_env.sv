class clamp_env extends uvm_env;

    `uvm_component_utils(clamp_env)
    clamp_scoreboard scoreboard;
    clamp_agent agent;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
        agent = clamp_agent::type_id::create("agent", this);
        scoreboard = clamp_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
