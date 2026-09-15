`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/29/2026 11:48:23 AM
// Design Name: 
// Module Name: prop_ctrl_pwm
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

// Top of the proportional-control loop: ties the controller, PWM generator, and
// the LED / 7-seg status displays together and drives the H-bridge motor pins.
module prop_ctrl_pwm #(parameter int BITS = 12, parameter int THRESHOLD = 0, parameter int PWM_CLK_FREQ_HZ = 490) (
    input logic             clk, reset,
    input logic signed [31:0] reference, k,
    input logic             ch_a, ch_b,
    output logic [15:0]     led,
    output logic [6:0]      seg,
    output logic [3:0]      an,
    output logic            motor_en, motor_in1, motor_in2
);
    // PWM clock = (PWM frequency) x (counts per period), so the counter rolls
    // over PWM_CLK_FREQ_HZ times per second
    localparam CLK_FREQ_HZ = PWM_CLK_FREQ_HZ*(2**BITS-1);

    logic [BITS-1:0]        pwm_cmp;  // duty-cycle command from the controller
    logic                   clk_divd; // slow clock for the PWM counter
    logic signed [31:0]     position, error_scaled;
    logic                   dir;

    // H-bridge direction pins are always opposite each other
    assign motor_in1        = dir;
    assign motor_in2        = ~dir;


    decoder_to_32_bit DECODER (
        .clk(clk),
        .reset(reset),
        .ch_a(ch_a),
        .ch_b(ch_b),
        .count(position)
    );

    // Proportional action
    controller #(.BITS(BITS)) CONTROLLER (
        .clk(clk),
        .reset(reset),
        .reference(reference),
        .position(position),
        .k(k),
        .error_scaled(error_scaled)
    );

    magnitude_clamp #(2**BITS - 1) MAG_CLAMP (
        .value(error_scaled),
        .clamped_value(pwm_cmp),
        .dir(dir)
    );

    clock_div #(.DESIRED_CLK_FREQ_HZ(CLK_FREQ_HZ)) CLK_DIVIDER (
        .clk(clk),
        .reset(reset),
        .clk_out(clk_divd)
    );

    // turn the duty command into the actual PWM waveform on motor_en
    pwm_n_bit #(.BITS(BITS),.THRESHOLD(THRESHOLD)) PWM (
        .clk(clk_divd),
        .reset(reset),
        .duty(pwm_cmp),
        .pwm_out(motor_en)
    );

    led_status LED_STATUS (
        .pwm_cmp(pwm_cmp[7:0]),
        .led(led),
        .dir(dir)
    );

    status_7seg #(.AN_CLK_FREQ_HZ(5_000)) SEVEN_SEG (
        .clk(clk),
        .reset(reset),
        .reference(reference),
        .an(an),
        .seg(seg)
    );

endmodule
