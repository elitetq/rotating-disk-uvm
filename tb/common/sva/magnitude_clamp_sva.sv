import uvm_pkg::*;
`include "uvm_macros.svh"
module magnitude_clamp_sva #(parameter int CLAMP_VAL) (
    input logic signed [31:0]               value,
    input logic [$clog2(CLAMP_VAL+1)-1:0]   clamped_value,
    input logic                             dir
);

    localparam logic signed [31:0] INT_MIN = 32'h8000_0000;

    always @(value) begin
        #0; // wait for all blocking statements (comb) to finish before checking
        // R-CLP-1 : dir should be 1 when value < 0, 0 otherwise.
        a_dir_valid: assert(value < 0 ? dir : !dir)
        else `uvm_error("SVA_magnitude_clamp","Failed R-CLP-1 assertion.");
        // R-CLP-2 : clamped value must be less than or equal to CLAMP_VAL.
        a_less_than_clamp_val: assert(clamped_value <= CLAMP_VAL)
        else `uvm_error("SVA_magnitude_clamp","Failed R-CLP-2 assertion");
        // R-CLP-3 : clamped_value should be correct for value = INT_MIN
        a_int_min_correctness: assert((value === INT_MIN) ? (clamped_value === CLAMP_VAL) : 1)
        else `uvm_error("SVA_magnitude_clamp","Failed R-CLP-3 assertion");
        // R-CLP-4 : clamped_value should settle within one delta of input change
        a_comb_settle: assert (clamped_value == dut_pkg::expected_clamp_val(value, CLAMP_VAL)
                               && dir == dut_pkg::expected_clamp_dir(value))
        else `uvm_error("SVA_magnitude_clamp","Failed R-CLP-4 assertion.");
    end

    // R-CLP-5 : CLAMP_VAL is always between [1:2**31-1]
    initial begin
        assert (CLAMP_VAL > 0)
        else `uvm_error("SVA_magnitude_clamp", "clamp_val is not > 0");
    end

endmodule
