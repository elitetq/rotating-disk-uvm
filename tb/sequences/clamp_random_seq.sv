class clamp_random_seq extends clamp_base_seq;
  `uvm_object_utils(clamp_random_seq)

  function new(string name = "clamp_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    if(!uvm_config_db#(int)::get(null,"","CLAMP_VAL",clamp_val)) `uvm_fatal("NOCFG","CLAMP_VAL could not be fetched from uvm db.");
    repeat(n_items) begin
      req = clamp_item::type_id::create("req");
      req.clamp_val = clamp_val;
      start_item(req);
      if (!req.randomize())
        `uvm_fatal("CLAMP_RANDOM_SEQ","Randomization failed.")
      finish_item(req);
    end
  endtask
endclass
