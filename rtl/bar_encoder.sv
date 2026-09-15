`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 07:53:13 PM
// Design Name: 
// Module Name: bar_encoder
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

// Thermometer (bar-graph) encoder: fills every bit from the most-significant
// set bit of value down to bit 0. A larger value lights up more of the bar,
// which is handy for driving an LED level meter.
module bar_encoder #(parameter int BITS) (
    input logic [BITS-1:0] value,
    output logic [BITS-1:0] bar
    );
    always_comb begin
        bar[BITS-1] = value[BITS-1];
        // walk down from the top bit, holding the OR of everything above us
        for(int i = BITS-2; i >= 0; i--) begin
            bar[i] = bar[i+1] | value[i];
        end
    end
endmodule
