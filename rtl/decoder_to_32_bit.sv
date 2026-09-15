`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:47:12 AM
// Design Name: 
// Module Name: decoder_to_32_bit
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

// Quadrature decoder: turns the encoder's A/B channels into a signed position
// count. first_value_priority works out direction and emits one pulse per step,
// and directional_counter counts those pulses up or down.
module decoder_to_32_bit (
    input logic                     clk, reset,
    input logic                     ch_a, ch_b,
    output logic signed [31:0]      count
);

    logic                   dir, pulse;

    first_value_priority AB_DIR (
        .clk(clk),
        .reset(reset),
        .ch_a(ch_a),
        .ch_b(ch_b),
        .dir(dir),
        .pulse(pulse)
    );

    directional_counter COUNTER (
        .clk(clk),
        .reset(reset),
        .en(pulse),
        .dir(dir),
        .count(count)
    );

endmodule
