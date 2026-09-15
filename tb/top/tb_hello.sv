`timescale 1ns/1ps

package hello_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class hello_test extends uvm_test;
    `uvm_component_utils(hello_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("HELLO", "UVM is alive on XSim", UVM_LOW)
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module tb_hello;
  import uvm_pkg::*;
  import hello_pkg::*;
  initial run_test("hello_test");
endmodule