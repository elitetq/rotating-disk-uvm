`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:49:21 AM
// Design Name: 
// Module Name: pwm_n_bit
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

// N-bit PWM generator. A free-running counter ramps 0..2^BITS-1 every period;
// the output is high while the counter sits below duty, so a larger duty means a
// wider pulse. THRESHOLD keeps the output off for very small duty values.
module pwm_n_bit #(parameter int BITS = 12, parameter int THRESHOLD = 0) (
    input logic             clk, reset,
    input logic [BITS-1:0]  duty,
    output logic            pwm_out
);
    logic [BITS-1:0]        D, Q; // Q is the current counter value, D the next
    assign pwm_out          = (Q <= duty) && (duty > THRESHOLD);

    always_ff @(posedge clk, posedge reset) begin
        if(reset) Q <= 0;
        else Q <= D;
    end

    // count up; wraps back to 0 on overflow to start the next period
    always_comb begin
        D = Q + 1;
    end
endmodule
