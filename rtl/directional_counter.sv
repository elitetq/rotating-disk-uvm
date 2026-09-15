`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:43:16 AM
// Design Name: 
// Module Name: directional_counter
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


// Up/down counter. When en pulses high it steps the count by one, in the
// direction chosen by dir (1 = up, 0 = down).
module directional_counter (
    input logic clk, reset, en, dir,
    output logic signed [31:0] count
);
    logic signed [31:0]         D, increment;

    assign increment            = 1;

    always_ff @(posedge clk, posedge reset) begin
        if(reset) begin
            count <= 0;
        end
        else begin
            if(en) count <= D; // only advance on an enable pulse
        end
    end

    // next-count value: add or subtract depending on direction
    always_comb begin
        D = dir ? (count + increment) : (count - increment);
    end

endmodule
