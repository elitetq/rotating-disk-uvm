# ---- include directories (for `include inside packages) ----
-i ../tb/common
-i ../tb/agents/clamp_agent
-i ../tb/env
-i ../tb/sequences
-i ../tb/tests

# ---- RTL ----
../rtl/magnitude_clamp.sv

# ---- TB common ----
../tb/common/dut_pkg.sv
../tb/common/clamp_if.sv

# ---- Agent / env / tests ----
../tb/agents/clamp_agent/clamp_agent_pkg.sv
../tb/env/clamp_env_pkg.sv
../tb/tests/clamp_tests_pkg.sv

# ---- Top ----
# SVA + bind added in B7 (bind_all.sv currently binds pwm_n_bit, which isn't compiled here)
../tb/top/tb_clamp_top.sv
