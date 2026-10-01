bind pwm_n_bit pwm_n_bit_sva #(
  .BITS      (BITS),
  .THRESHOLD (THRESHOLD)
) u_pwm_sva (
  .clk     (clk),
  .reset   (reset),
  .duty    (duty),
  .Q       (Q),
  .pwm_out (pwm_out)
);
