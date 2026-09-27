import uvm_pkg::*;
`include "uvm_macros.svh"
// Bound into pwm_n_bit — see bind_all.sv. The RTL is never edited.
// Note this module receives Q, an internal DUT signal. `bind` can see internals,
// which is exactly what makes it useful for white-box checking.
module pwm_n_bit_sva #(parameter int BITS = 8, parameter int THRESHOLD = 0) (
  input logic            clk,
  input logic            reset,
  input logic [BITS-1:0] duty,
  input logic [BITS-1:0] Q,
  input logic            pwm_out
);

  default clocking @(posedge clk); endclocking

  // R-PWM-2 : the instantaneous output relation, every single cycle.
  a_out_relation: assert property (
    disable iff(reset)
    // one clock delay, reset must be low for 2 clock periods before assertion is checked to combat X propagation delay
    @(posedge clk) !$past(reset) |-> (pwm_out == ((duty > THRESHOLD) && (Q <= duty)))
  ) else `uvm_error("SVA_pwm_n_bit","Failed R-PWM-2 assertion.");

  // R-PWM-1 : the counter increments by one every cycle and wraps cleanly.
  a_counter_inc: assert property (
    disable iff(reset)
    @(posedge clk) $past(!reset) |-> ($past(Q)+1'b1 == Q)
  ) else `uvm_error("SVA_pwm_n_bit","Failed R-PWM-1 assertion.");

  // R-PWM-4 : reset forces the counter to zero on the next edge.
  a_reset_clears: assert property (
    disable iff (1'b0) // override default assertion
    @(posedge clk) reset |=> (Q == 0)
  ) else `uvm_error("SVA_pwm_n_bit","Failed R-PWM-5 assertion.");

  // R-PWM-5 : parameter legality. 
  initial begin
    assert (THRESHOLD >= 0 && THRESHOLD < 2**BITS-3)
      else $fatal(1, "pwm_n_bit: THRESHOLD=%0d illegal for BITS=%0d", THRESHOLD, BITS);
  end

endmodule
