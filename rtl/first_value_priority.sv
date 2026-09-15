`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:35:52 AM
// Design Name: 
// Module Name: first_value_priority
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

// Direction detector for a quadrature encoder. Channels A and B are 90 degrees
// out of phase; which one leads tells us the spin direction. We watch the
// transitions and emit dir (1 = forward, 0 = reverse) plus a one-clock pulse for
// each valid step. The lock bits make sure each motion only counts once.
module first_value_priority (
    input logic             clk, reset,
    input logic             ch_a, ch_b,
    output logic            dir, pulse
);
    // [0] = synchronized A/B now, [1] = one-clock-older snapshot for edge detection
    logic [1:0]             a_sync, b_sync;
    logic                   ff1_wire;
    logic [1:0]             up_lock, down_lock; // block a second count until A&B return to 00

    assign dir                = ff1_wire;

    synchronizer SYNC_A (
        .clk(clk),
        .in(ch_a),
        .out(a_sync[0])
    );
    synchronizer SYNC_B (
        .clk(clk),
        .in(ch_b),
        .out(b_sync[0])
    );

    always_ff @(posedge clk, posedge reset) begin
        pulse <= 0;
        if(reset) begin
            ff1_wire <= 0;
            a_sync[1] <= 0;
            b_sync[1] <= 0;
            up_lock[1] <= 0;
            down_lock[1] <= 0;
        end
        else begin
            a_sync[1] <= a_sync[0];
            b_sync[1] <= b_sync[0];
            up_lock[1] <= up_lock[0];
            down_lock[1] <= down_lock[0];

            // Whenever A & B are both zero
            if(~a_sync[0] && ~b_sync[0] && ~a_sync[1] && ~b_sync[1]) begin
                up_lock[0] <= 0;
                down_lock[0] <= 0;
            end
            else begin
                // 00 -> 10 or 01 -> 00
                if((~a_sync[1] && a_sync[0] && ~b_sync[0]) || (b_sync[1] && ~b_sync[0] && ~a_sync[0])) begin
                    if(!up_lock[1]) begin
                        ff1_wire <= 1;
                        pulse <= 1;
                        up_lock[0] <= 1;
                        down_lock[0] <= 0;
                    end
                end

                // 00 -> 01 or 10 -> 00
                else if((~b_sync[1] && b_sync[0] && ~a_sync[0]) || (a_sync[1] && ~a_sync[0] && ~b_sync[0])) begin
                    if(!down_lock[1]) begin
                        ff1_wire <= 0;
                        pulse <= 1;
                        down_lock[0] <= 1;
                        up_lock[0] <= 0;
                    end
                end
            end
        end
    end

endmodule
