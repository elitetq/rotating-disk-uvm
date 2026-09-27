typedef uvm_sequencer #(clamp_item) clamp_sequencer;

class clamp_agent extends uvm_agent;

    `uvm_component_utils(clamp_agent)

    clamp_driver    driver;
    clamp_sequencer sequencer;
    clamp_monitor   monitor;

    uvm_analysis_port #(clamp_transaction) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap_clamp_agent", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = clamp_monitor::type_id::create("monitor", this);

      if (get_is_active() == UVM_ACTIVE) begin
        driver    = clamp_driver::type_id::create("driver", this);
        sequencer = clamp_sequencer::type_id::create("sequencer", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      monitor.ap.connect(ap);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
