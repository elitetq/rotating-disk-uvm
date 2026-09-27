`timescale 1ns/1ps

module tb_clamp_top #(parameter int CLAMP_VAL = 255);

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import clamp_tests_pkg::*;

  localparam int  W          = $clog2(CLAMP_VAL + 1);
  localparam time CLK_PERIOD = 10ns;      // 100 MHz

  logic clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  clamp_if vif (.clk(clk));

  logic [W-1:0] dut_clamped;

  magnitude_clamp #(.CLAMP_VAL(CLAMP_VAL)) DUT (
    .value         (vif.value),
    .clamped_value (dut_clamped),
    .dir           (vif.dir)
  );

  assign vif.clamped_value = dut_clamped;  // zero-extend into the 32-bit interface bus

  initial begin
    uvm_config_db#(virtual clamp_if)::set(null, "*", "vif",       vif);
    uvm_config_db#(int)::set             (null, "*", "CLAMP_VAL", CLAMP_VAL);
    run_test();                            // test name comes from +UVM_TESTNAME
  end

endmodule
