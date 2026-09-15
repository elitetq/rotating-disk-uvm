`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 07:39:38 PM
// Design Name: 
// Module Name: led_status
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


// Drives the 16 board LEDs as a centre-out bar graph showing the PWM effort.
// The bar grows from the middle towards whichever side dir points to.
module led_status (
    input logic [7:0] pwm_cmp,
    input logic dir,
    output logic [15:0] led
    );
    logic [7:0] led_array;     // bar-graph pattern for the PWM magnitude
    logic [7:0] led_array_rev; // same bar, mirrored so it grows the other way

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin
            assign led_array_rev[i] = led_array[7-i];
        end
    endgenerate

    // put the bar on the left or right half depending on direction
    assign led = dir ? {8'd0, led_array_rev} : {led_array, 8'd0};

    bar_encoder #(.BITS(8)) BAR_LED (
        .value(pwm_cmp),
        .bar(led_array)
    );
endmodule