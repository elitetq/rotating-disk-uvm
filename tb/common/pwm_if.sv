interface pwm_if(input logic clk);

    localparam MAX_BITS = 16; // Adjust if more slack is needed for UVM

    logic                   reset;
    logic [MAX_BITS-1:0]    duty;
    logic                   pwm_out;

    // Driver clock rules, reset and duty are adjustable but pwm_out is strictly determined by the module logic
    clocking drv_cb @(posedge clk);
        default input #1step output #2ns;
        input pwm_out;
        output reset, duty;
    endclocking


    // Monitor clock rules, everything is readonly (input)
    clocking mon_cb @(posedge clk);
        default input #1step;
        input pwm_out, reset, duty;
    endclocking

    modport DRV (clocking drv_cb);
    modport MON (clocking mon_cb);


endinterface