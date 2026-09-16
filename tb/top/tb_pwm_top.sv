`timescale 1ns/1ps

module tb_pwm_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
//   import pwm_tests_pkg::*;

  localparam int  BITS       = 8;
  localparam int  THRESHOLD  = 14;
  localparam time CLK_PERIOD = 10ns;      // 100 MHz

  logic clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  pwm_if vif (.clk(clk));

  pwm_n_bit #(.BITS(BITS), .THRESHOLD(THRESHOLD)) DUT (
    .clk     (clk),
    .reset   (vif.reset),
    .duty    (vif.duty[BITS-1:0]),        // narrow the wide interface bus
    .pwm_out (vif.pwm_out)
  );

  // GATE A1 ONLY: hardcoded stimulus, delete once the driver exists.
  // initial begin
  //   vif.reset = 1; vif.duty = '0;
  //   repeat(5) @(posedge clk);
  //   vif.duty = 100;
  //   vif.reset = 0;
  //   repeat(3 * 2**BITS) @(posedge clk);
  //   $finish;
  // end


  initial begin
    uvm_config_db#(virtual pwm_if)::set(null, "*", "vif",       vif);
    uvm_config_db#(int)::set          (null, "*", "BITS",       BITS);
    uvm_config_db#(int)::set          (null, "*", "THRESHOLD",  THRESHOLD);
    run_test();                            // test name comes from +UVM_TESTNAME
  end

endmodule
