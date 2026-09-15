`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:45:47 AM
// Design Name: 
// Module Name: magnitude_clamp
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

// Splits a signed value into a magnitude and a sign. The magnitude is capped at
// CLAMP_VAL (so it always fits the output width) and dir carries the sign.
module magnitude_clamp #(parameter int CLAMP_VAL) (
    input logic signed [31:0] value,
    output logic [$clog2(CLAMP_VAL+1)-1:0] clamped_value,
    output logic dir
);
    logic [31:0] value_abs;

    // take the absolute value and remember whether it was negative
    always_comb begin
        if(value < 0) begin
            value_abs = ~value + 1; // two's-complement negate -> magnitude
            dir = 1;
        end
        else begin
            value_abs = value;
            dir = 0;
        end
    end

    // saturate the magnitude so it never exceeds what the output can hold
    always_comb begin
        if(value_abs > CLAMP_VAL) clamped_value = CLAMP_VAL;
        else clamped_value = value_abs[$clog2(CLAMP_VAL+1)-1:0];
    end

endmodule
