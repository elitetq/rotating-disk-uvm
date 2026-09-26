// Swapped in for pwm_driver by a factory override in the tests that need it
// (pwm_duty_change_test, pwm_reset_test). run_phase is inherited unchanged; only drive() differs.
// Same contract as the parent: every item starts and ends on a period boundary.

class pwm_ext_driver extends pwm_driver;

  `uvm_component_utils(pwm_ext_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive(pwm_item item);
    pwm_ext_item ext;

    if (!$cast(ext, item)) begin // plain pwm_item, behave exactly like the parent
      super.drive(item);
      return;
    end

    `uvm_info("DRIVER",$sformatf("driving duty = %0d at offset %0d for %0d hold periods, reset = %0b at +%0d for %0d cycles.",
      ext.duty, ext.offset_cycles, ext.hold_periods, ext.do_reset, ext.reset_at, ext.reset_cycles),UVM_MEDIUM)

    repeat(ext.offset_cycles) @(vif.drv_cb); // previous duty is still applied during the offset
    vif.drv_cb.duty <= ext.duty;

    if (ext.do_reset) begin
      repeat(ext.reset_at) @(vif.drv_cb);
      vif.drv_cb.reset <= 1;
      repeat(ext.reset_cycles) @(vif.drv_cb);
      vif.drv_cb.reset <= 0;
      repeat(ext.hold_periods*(2**bits)) @(vif.drv_cb); // counter restarted at release, so count from there
    end else begin
      repeat(ext.hold_periods*(2**bits) - ext.offset_cycles) @(vif.drv_cb); // end back on the original boundary
    end
  endtask

endclass
