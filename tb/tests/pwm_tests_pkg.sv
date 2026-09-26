package pwm_tests_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import pwm_env_pkg::*;
    import pwm_agent_pkg::*;

    `include "pwm_base_seq.sv"
    `include "pwm_smoke_seq.sv"
    `include "pwm_duty_change_seq.sv"
    `include "pwm_random_seq.sv"
    `include "pwm_reset_seq.sv"
    `include "pwm_corner_seq.sv"
    `include "pwm_base_test.sv"
    `include "pwm_smoke_test.sv"
    `include "pwm_random_test.sv"
    `include "pwm_reset_test.sv"
    `include "pwm_duty_change_test.sv"
    `include "pwm_corner_test.sv"
endpackage