// XSIM has no BUFG primitive, so this is a stub file to circumvent that error

module BUFG(
    input logic I,
    output logic O
);
    assign O = I;
endmodule