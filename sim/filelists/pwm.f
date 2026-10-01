# ---- include directories (for `include inside packages) ----
-i ../tb/common
-i ../tb/agents/pwm_agent
-i ../tb/env
-i ../tb/sequences
-i ../tb/tests

# ---- RTL ----
../rtl/pwm_n_bit.sv

# ---- TB common ----
../tb/common/dut_pkg.sv
../tb/common/pwm_if.sv

# ---- Agent / env / tests / sva ----
../tb/agents/pwm_agent/pwm_agent_pkg.sv
../tb/env/pwm_env_pkg.sv
../tb/tests/pwm_tests_pkg.sv
../tb/common/sva/pwm_n_bit_sva.sv

# ---- Bind + top ----
../tb/common/sva/bind/bind_pwm.sv
../tb/top/tb_pwm_top.sv
