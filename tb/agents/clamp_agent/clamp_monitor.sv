class clamp_transaction extends uvm_sequence_item;
    int value;
    int clamped_value;
    bit dir;

    `uvm_object_utils_begin(clamp_transaction)
        `uvm_field_int(value,         UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(clamped_value, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(dir,           UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "clamp_transaction"); super.new(name); endfunction
endclass

class clamp_monitor extends uvm_monitor;
    `uvm_component_utils(clamp_monitor)

    virtual clamp_if vif;

    uvm_analysis_port #(clamp_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ap = new("ap_monitor", this);

        if(!uvm_config_db#(virtual clamp_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "vif could not be resolved in monitor.")
    endfunction

    virtual task run_phase(uvm_phase phase);
        clamp_transaction t;
        @(vif.mon_cb);
        forever begin
            @(vif.mon_cb);
            t = clamp_transaction::type_id::create("clamp_t");
            t.value = vif.mon_cb.value;
            t.clamped_value = vif.mon_cb.clamped_value;
            t.dir = vif.mon_cb.dir;
            ap.write(t);
        end
    endtask

endclass
