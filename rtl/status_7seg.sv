`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/30/2026 02:43:06 AM
// Design Name: 
// Module Name: status_7seg
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


//  ---a---
// |       |
// f       b
// |       |
//  ---g---
// |       |
// e       c
// |       |
//  ---d---
// seg[6:0] = {CG,CF,CE,CD,CC,CB,CA} = {g,f,e,d,c,b,a}, active LOW

typedef enum logic [6:0] {
    //                         gfedcba
    // Digits
    SEG_0          = 7'b1000000,
    SEG_1          = 7'b1111001,
    SEG_2          = 7'b0100100,
    SEG_3          = 7'b0110000,
    SEG_4          = 7'b0011001,
    SEG_5          = 7'b0010010,
    SEG_6          = 7'b0000010,
    SEG_7          = 7'b1111000,
    SEG_8          = 7'b0000000,
    SEG_9          = 7'b0010000,
    // Hex letters (b/d lowercase to avoid clash with 8/0)
    SEG_A          = 7'b0001000,
    SEG_b          = 7'b0000011,
    SEG_C          = 7'b1000110,
    SEG_d          = 7'b0100001,
    SEG_E          = 7'b0000110,
    SEG_F          = 7'b0001110,
    // Additional letters
    SEG_H          = 7'b0001001,
    SEG_J          = 7'b1100001,
    SEG_L          = 7'b1000111,
    SEG_n          = 7'b0101011,
    SEG_o          = 7'b0100011,
    SEG_P          = 7'b0001100,
    SEG_r          = 7'b0101111,
    SEG_t          = 7'b0000111,
    SEG_U          = 7'b1000001,
    SEG_y          = 7'b0010001,
    // Symbols
    SEG_MINUS      = 7'b0111111,
    SEG_UNDERSCORE = 7'b1110111,
    SEG_DEGREE     = 7'b0011100,
    SEG_BLANK      = 7'b1111111
    // Aliases (same encoding, not in enum):
    // SEG_O = SEG_0, SEG_S = SEG_5, SEG_G = SEG_6, SEG_Z = SEG_2
} seg7_e;

// Shows the reference position on the 4-digit 7-segment display, in degrees,
// with a leading minus sign for negative angles. The four digits share one set
// of segment wires, so we light them one at a time fast enough to look steady.
module status_7seg #(parameter int AN_CLK_FREQ_HZ) (
    input  logic        clk, reset,
    input  logic signed [31:0]  reference,
    output logic [3:0]  an,
    output logic [6:0]  seg
    );
    logic        clk_divd, dir;
    logic [31:0] abs_reference;
    logic [9:0]  reference_deg;
    logic [1:0]  an_cnt = '0;                  // which digit is active right now (initialized so simulation doesn't stick at 'x)
    logic [3:0]  hundreds, tens, ones;

    assign dir          = reference >= 0;       // 1 = positive angle (no minus sign)
    assign abs_reference = reference[31] ? -reference : reference;

    // encoder gives 128 ticks per 90 degrees, so convert ticks -> degrees
    assign reference_deg = (abs_reference[9:0] * 18'd90) / 18'd128;

    // split the angle into its decimal digits
    assign hundreds = (reference_deg / 100) % 10;
    assign tens     = (reference_deg / 10) % 10;
    assign ones     =  reference_deg % 10;

    // lookup table: digit value -> 7-segment pattern
    seg7_e digit_to_seg [0:9] = '{SEG_0,SEG_1,SEG_2,SEG_3,SEG_4,SEG_5,SEG_6,SEG_7,SEG_8,SEG_9};

    clock_div #(.DESIRED_CLK_FREQ_HZ(AN_CLK_FREQ_HZ)) CLOCK_DIV (
        .reset(1'b0),
        .clk(clk),
        .clk_out(clk_divd)
    );

    // step the active-digit counter each slow tick to scan across the display
    always_ff @(posedge clk_divd) begin
        an_cnt <= an_cnt + 1;
    end

    // anodes are active LOW: pull exactly one digit low to enable it
    always_comb begin
        an         = 4'b1111;
        an[an_cnt] = 1'b0;
    end

    // pick the segment pattern for whichever digit is currently active
    always_comb begin
        if(reset) begin
            // while held in reset, spell out "5Et" (Set) to show reset state and ability to set new position
            case (an_cnt)
                2'd0: seg = SEG_t;
                2'd1: seg = SEG_E;
                2'd2: seg = SEG_5;
                default: seg = SEG_BLANK;
            endcase
        end
        else begin
            case (an_cnt)
                2'd0: seg = digit_to_seg[ones];
                2'd1: seg = digit_to_seg[tens];
                2'd2: seg = digit_to_seg[hundreds];
                2'd3: seg = (dir ? SEG_BLANK : SEG_MINUS);
                default: seg = SEG_BLANK;
            endcase
        end
    end

endmodule
