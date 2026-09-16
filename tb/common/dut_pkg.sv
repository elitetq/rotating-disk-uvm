// Golden models for the rotating-disk design.
// Pure functions only — no classes, no state, no UVM dependency.
// Every function here is derived in uvm_plan/02_design_under_test.md.
package dut_pkg;

  // ------------------------------------------------------------------
  // pwm_n_bit  (02_design_under_test.md §1)
  //
  //   pwm_out is high exactly while  duty > THRESHOLD  and  Q <= duty,
  //   so Q spans the closed range [0, duty] — duty+1 counts — or nothing at all.
  //
  //   high_cycles = (duty > THRESHOLD) ? duty + 1 : 0   per 2**BITS clocks
  // ------------------------------------------------------------------
  function automatic int expected_pwm_high(input int duty, input int threshold);
    return duty > threshold ? duty + 1 : 0;
  endfunction

  function automatic int pwm_period(input int bits);
    return 2**bits;
  endfunction

endpackage
