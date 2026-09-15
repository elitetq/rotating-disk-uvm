`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:41:15 AM
// Design Name: 
// Module Name: clock_div
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Divides the board clock (CLK_FREQ_HZ) down to DESIRED_CLK_FREQ_HZ by counting
// clock edges and toggling an internal clock every half period.
module clock_div #(parameter int DESIRED_CLK_FREQ_HZ, parameter int CLK_FREQ_HZ = 100_000_000) (
    input logic clk, reset,
    output logic clk_out
);
    // toggle every TICKS edges -> a full output period is 2*TICKS input edges
    localparam int TICKS = (CLK_FREQ_HZ/DESIRED_CLK_FREQ_HZ)/2;
    localparam int BITS = $clog2(TICKS);

    // initial values matter in simulation: without them these start as 'x and
    // the divided clock never toggles when reset is tied low (see status_7seg)
    logic clk_int = 1'b0;      // divided clock before the global buffer
    logic [BITS-1:0] counter = '0;

    always_ff @(posedge clk, posedge reset) begin
        if(reset) begin
            clk_int <= 0;
            counter <= 0;
        end
        else begin
            counter <= counter + 1;
            if(counter == TICKS-1) begin
                counter <= 0;
                clk_int <= ~clk_int; // half period elapsed, flip the output
            end
        end
    end

    // route the generated clock onto a dedicated global clock buffer so it can
    // safely drive other sequential logic on the FPGA
    BUFG bufg_inst (
        .I (clk_int),
        .O (clk_out)
    );

endmodule