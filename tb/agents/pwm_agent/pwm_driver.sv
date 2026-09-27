class pwm_driver extends uvm_driver #(pwm_item);

  `uvm_component_utils(pwm_driver)

  virtual pwm_if  vif; // vif handle is not instantiated instantly, but rather in build_phase
  int             bits; // get from db to find out pwm bits

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pwm_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_full_name(), {"virtual interface not set for ", get_full_name()})
    if (!uvm_config_db#(int)::get(this, "", "BITS", bits))
      `uvm_fatal(get_full_name(), "BITS not set")
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Pins reset to known state
    vif.drv_cb.duty <= '0;
    vif.drv_cb.reset <= 1;
    repeat(2*(2**bits)) @(vif.drv_cb); // two full pwm periods
    vif.drv_cb.reset <= 0;

    forever begin
      automatic pwm_item item;
      seq_item_port.get_next_item(item);   // blocks until the sequencer has one
      drive(item);
      seq_item_port.item_done();          // tells the sequencer we are ready for more
    end
  endtask

  virtual task drive(pwm_item item);
    vif.drv_cb.duty <= item.duty;
    repeat(item.hold_periods*(2**bits)) @(vif.drv_cb);
    `uvm_info("DRIVER",$sformatf("driving duty = %0d for %0d hold periods.", item.duty, item.hold_periods),UVM_HIGH)
  endtask

endclass
