// Golden models for the rotating-disk design.
// Pure functions only — no classes, no state, no UVM dependency.
// Every function here is derived in uvm_plan/02_design_under_test.md.
package dut_pkg;

  // ------------------------------------------------------------------
  // pwm_n_bit
  //
  //   pwm_out is high exactly while  duty > THRESHOLD  and  Q <= duty,
  //   so Q spans the closed range [0, duty] — duty+1 counts — or nothing at all.
  //
  //   high_cycles = (duty > THRESHOLD) ? duty + 1 : 0   per 2**BITS clocks
  // ------------------------------------------------------------------
  function automatic int expected_pwm_high(input int duty, input int threshold);
    return duty > threshold ? duty + 1 : 0;
  endfunction

  function automatic longint pwm_period(input int bits);
    return 64'd1 << bits;                 // 2**bits in int is 0 at bits = 32
  endfunction

  // ------------------------------------------------------------------
  // magnitude_clamp
  //
  //   clamped_value = min(|value|, CLAMP_VAL) — a magnitude, never negative.
  //   |INT_MIN| = 2**31 does not fit in an int, so the magnitude is taken in a longint.
  //
  //   Clamp direction checks if the current value is less than 0, setting it to 1 if negative or 0 if
  //   greater than or equal to 0. This lets us keep the negative nature of the number even though
  //   we're taking the absolute value.
  //
  // ------------------------------------------------------------------

  function automatic int expected_clamp_val(input int value, input int clamp_val);
    longint mag = value;                  // widen before negating
    if(mag < 0) mag = -mag;
    return mag > clamp_val ? clamp_val : mag;
  endfunction

  function automatic int expected_clamp_dir(input int value);
    return value < 0;
  endfunction

  function automatic int clamp_max_width(int clamp_val);
    return $clog2(clamp_val+1);
  endfunction

endpackage
