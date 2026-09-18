// 
typedef uvm_sequencer #(pwm_item) pwm_sequencer; // doesnt need its own file

class pwm_agent extends uvm_agent;

    `uvm_component_utils(pwm_agent)

    pwm_driver    driver;
    pwm_sequencer sequencer;
    pwm_monitor   monitor; // not implemented yet

    uvm_analysis_port #(pwm_transaction) ap;    // forwarded from the monitor

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap      = new("ap_agent", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = pwm_monitor::type_id::create("monitor", this);

      // is_active comes from uvm_agent; the env sets it via config_db.
      // A PASSIVE agent has a monitor only — which is exactly what Phase D needs
      // when it reuses this agent to watch the PWM output inside prop_ctrl_pwm.
      if (get_is_active() == UVM_ACTIVE) begin
        driver    = pwm_driver::type_id::create("driver", this);
        sequencer = pwm_sequencer::type_id::create("sequencer", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      monitor.ap.connect(ap);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
