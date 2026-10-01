bind magnitude_clamp magnitude_clamp_sva #(
  .CLAMP_VAL (CLAMP_VAL)
) u_mclamp_sva (
  .value            (value),
  .clamped_value    (clamped_value),
  .dir              (dir)
);
