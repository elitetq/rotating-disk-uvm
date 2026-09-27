class clamp_base_seq extends uvm_sequence #(clamp_item);
  `uvm_object_utils(clamp_base_seq)

  int n_items = 20;
  int clamp_val;

  function new(string name = "clamp_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    if(!uvm_config_db#(int)::get(null,"","CLAMP_VAL",clamp_val)) `uvm_fatal("NOCFG","CLAMP_VAL could not be fetched from uvm db.");
    repeat(n_items) begin
      req = clamp_item::type_id::create("req");
      req.clamp_val = clamp_val;
      start_item(req);
      if (!req.randomize() with {
        value dist {
          32'sh8000_0000 := 10,
          [32'sh8000_0001:-clamp_val-2] :/ 10,
          [-clamp_val-1:-clamp_val+1] := 10,
          [-clamp_val+2:-2] :/ 10,
          [-1:1] := 10,
          [2:clamp_val-2] :/ 10,
          [clamp_val-1:clamp_val+1] := 10,
          [clamp_val+2:32'sh7FFF_FFFE] :/ 10,
          32'sh7FFF_FFFF :/ 10
        };
      })
        `uvm_fatal("CLAMP_BASE_SEQ","Randomization failed.")
      finish_item(req);
    end
  endtask
endclass
