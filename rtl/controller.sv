`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 01:33:07 PM
// Design Name: 
// Module Name: controller
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


// Proportional feedback controller. Reads the encoder position, compares it to
// the reference (target) position, scales that error by the gain k, then clamps
// the result into a PWM command and a direction bit.
module controller #(parameter int BITS) (
    input logic             clk, reset, 
    input logic signed [31:0] reference, position,
    input logic [31:0]      k,
    output logic [31:0]     error_scaled
    );

    // position is the global decoder position relative to where we started (reset HIGH)
    logic signed [31:0]            ref_position, error;
    logic signed [63:0]            error_scaled_int;

    // latch the target position every clock (held at 0 during reset)
    always_ff @(posedge clk, posedge reset) begin
        if(reset) begin
            ref_position <= 0;
        end
        else begin
            ref_position <= reference;
        end
    end


    // error is how far we are from the target (current position - reference)
    assign error            = position - ref_position;

    // proportional term: multiply the error by the gain k (are you multiplying signed or unsigned?)
    assign error_scaled_int = error * k; // 64 bits wide
    assign error_scaled = error_scaled_int[31:0]; // truncate down to 32 bits

endmodule
