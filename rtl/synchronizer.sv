`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:37:08 AM
// Design Name: 
// Module Name: synchronizer
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

// Two-flip-flop synchronizer. An asynchronous input (like an encoder channel)
// can change right at a clock edge and cause metastability; passing it through
// two registers gives it time to settle before the rest of the logic uses it.
module synchronizer(
    input logic clk,
    input logic in,
    output logic out
);
    logic int_wire; // first stage, where metastability is allowed to settle

    always_ff @(posedge clk) begin
        int_wire <= in;
        out <= int_wire;
    end
endmodule