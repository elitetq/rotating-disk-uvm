class clamp_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(clamp_scoreboard)

    uvm_analysis_imp #(clamp_transaction, clamp_scoreboard) analysis_export;

    protected int clamp_val;

    protected int pass;
    protected int fail;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        pass = 0;
        fail = 0;
        analysis_export = new("clamp_scoreboard_analysis_export", this);

        if (!uvm_config_db#(int)::get(this, "", "CLAMP_VAL", clamp_val))
            `uvm_fatal("NOVAR", "No CLAMP_VAL set in uvm_config_db")
    endfunction

    virtual function void write(clamp_transaction t);
        automatic int error_flag = 0; // Used so fail / pass can be incremented once
        if(t.clamped_value !== expected_clamp_val(t.value,clamp_val)) begin
            `uvm_error("clamp_scoreboard",$sformatf("Invalid clamped_val: expected: %0d, Got: %0d",expected_clamp_val(t.value,clamp_val),t.clamped_value))
            error_flag = 1;
        end
        if(t.dir !== expected_clamp_dir(t.value)) begin
            `uvm_error("clamp_scoreboard",$sformatf("Invalid dir: expected: %0d, Got: %0d",expected_clamp_dir(t.value),t.dir))
            error_flag = 1;
        end
        if(error_flag) fail += 1;
        else pass += 1;

    endfunction

    function void check_phase(uvm_phase phase);
        if(fail == 0 && pass > 0)
            `uvm_info("clamp_scoreboard", $sformatf("Your clamp module passed all %0d tests!", pass), UVM_LOW)
        else
            `uvm_error("clamp_scoreboard", $sformatf("Your clamp module failed testing. %0d errors and %0d passes (%0d total)", fail, pass, fail + pass))
    endfunction

endclass
