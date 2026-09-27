class clamp_driver extends uvm_driver #(clamp_item);

  `uvm_component_utils(clamp_driver)

  virtual clamp_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual clamp_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_full_name(), {"virtual interface not set for ", get_full_name()})
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.drv_cb.value <= '0;
    @(vif.drv_cb)

    forever begin
      automatic clamp_item item;
      seq_item_port.get_next_item(item);
      drive(item);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive(clamp_item item);
    vif.drv_cb.value <= item.value;
    @(vif.drv_cb)
    `uvm_info("CLAMP",$sformatf("driving magnitude_clamp with value = %0d.", item.value),UVM_HIGH)
  endtask

endclass
