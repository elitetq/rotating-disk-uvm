# ---- include directories (for `include inside packages) ----
-i ../tb/common
-i ../tb/agents/pwm_agent
-i ../tb/env
-i ../tb/tests

# ---- RTL ----
../rtl/pwm_n_bit.sv

# ---- TB common ----
../tb/common/dut_pkg.sv
../tb/common/pwm_if.sv
../tb/common/sva/pwm_n_bit_sva.sv

# ---- Agent / env / tests ----
../tb/agents/pwm_agent/pwm_agent_pkg.sv
../tb/env/pwm_env_pkg.sv
../tb/tests/pwm_tests_pkg.sv

# ---- Bind + top ----
../tb/common/sva/bind_all.sv
../tb/top/tb_pwm_top.sv
