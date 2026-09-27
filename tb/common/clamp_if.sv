interface clamp_if(input logic clk);

    logic signed [31:0] value;
    logic        [31:0] clamped_value; // wide; the top zero-extends the DUT output
    logic               dir;

    clocking drv_cb @(posedge clk);
        default input #1step output #2ns;
        output value;
        input  clamped_value, dir;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input value, clamped_value, dir;
    endclocking

    modport DRV (clocking drv_cb);
    modport MON (clocking mon_cb);

endinterface
