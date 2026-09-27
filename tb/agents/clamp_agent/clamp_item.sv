class clamp_item extends uvm_sequence_item;

  rand bit signed [31:0] value;
  int clamp_val;                     // set by the sequence before randomize()

  `uvm_object_utils_begin(clamp_item)
    `uvm_field_int(value,     UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(clamp_val, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "clamp_item");
    super.new(name);
  endfunction

endclass
