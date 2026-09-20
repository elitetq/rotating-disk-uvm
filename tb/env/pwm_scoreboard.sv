class pwm_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(pwm_scoreboard)

    uvm_analysis_imp #(pwm_transaction, pwm_scoreboard) analysis_export; // points to agents analysis_port, which is forwarded to a monitor
    // better abstraction, scoreboard has no idea a monitor exists, its just handed information from the agent.

    protected int threshold;
    
    protected int pass;
    protected int fail;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        pass = 0;
        fail = 0;
        analysis_export = new("pwm_scoreboard_analysis_export", this);

        if (!uvm_config_db#(int)::get(this, "", "THRESHOLD", threshold))
            `uvm_fatal("NOVAR", {"No THRESHOLD set in uvm_config_db"});
    endfunction

    virtual function void write(pwm_transaction pwmt);
        if(!pwmt.valid_period) begin // not a valid period
            `uvm_info("NOPER","Given period is not valid, skipping transaction.", UVM_HIGH);
        end else begin
            if(pwmt.high_cycles != expected_pwm_high(pwmt.duty,threshold)) begin
                fail += 1;
            end else begin
                pass += 1;
            end

        end
    endfunction

    // Check results
    function void check_phase(uvm_phase phase);
        if(fail == 0 && (fail + pass > 0)) begin
            if(fail+pass > 0)
                `uvm_info("pwm_scoreboard",$sformatf("Your pwm module passed all %0d tests!",pass),UVM_HIGH)
            else
                `uvm_error("pwm_scoreboard",$sformatf("Your pwm module ran 0 tests. %0d errors and %0d passes (%0d total)", fail, pass, fail + pass))

        end else begin
            `uvm_error("pwm_scoreboard",$sformatf("Your pwm module failed testing. %0d errors and %0d passes (%0d total)", fail, pass, fail + pass))
        end
    endfunction

endclass