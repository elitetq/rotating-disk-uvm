typedef enum { V_ZERO, V_ONE, V_MONE, V_MID, V_MMID, V_CLAMP_M1, V_MCLAMP_M1, V_CLAMP, V_MCLAMP, V_CLAMP_P1, V_MCLAMP_P1, V_SAT_P, V_SAT_M, V_INT_MAX, V_INT_MIN} value_category_e;

class clamp_coverage extends uvm_subscriber #(clamp_transaction);
    `uvm_component_utils(clamp_coverage)

    int clamp_val;

    localparam int INT_MAX = 32'h7FFF_FFFF;
    localparam int INT_MIN = 32'h8000_0000;

    value_category_e value_c;
    /*
        V_ZERO      - value = 0
        V_ONE       - value = 1
        V_MONE      - value = -1
        V_MID       - value = [2:CLAMP_VAL-2]
        V_MMID      - value = [-2:-CLAMP_VAL+2]
        V_CLAMP_M1  - value = CLAMP-1
        V_MCLAMP_M1 - value = -CLAMP-1
        V_CLAMP     - value = CLAMP
        V_MCLAMP    - value = -CLAMP
        V_CLAMP_P1  - value = CLAMP+1
        V_MCLAMP_P1 - value = -CLAMP+1
        V_SAT_P     - value = [CLAMP+2:INT_MAX-1]
        V_SAT_M     - value = [-CLAMP-2:INT_MIN+1]
        V_INT_MIN   - value = INT_MIN
        V_INT_MAX   - value = INT_MAX
    */

    covergroup cg_values;
        option.per_instance = 1;

        cp_values:        coverpoint value_c;
    endgroup

    protected function value_category_e classify_value(int value);
        if      (value == 0) return V_ZERO;
        else    if(value == 1) return V_ONE;
        else    if(value == -1) return V_MONE;
        else    if(value == clamp_val-1) return V_CLAMP_M1;
        else    if(value == -clamp_val-1) return V_MCLAMP_M1;
        else    if(value == clamp_val) return V_CLAMP;
        else    if(value == -clamp_val) return V_MCLAMP;
        else    if(value == clamp_val+1) return V_CLAMP_P1;
        else    if(value == -clamp_val+1) return V_MCLAMP_P1;
        else    if(value == INT_MAX) return V_INT_MAX;
        else    if(value == INT_MIN) return V_INT_MIN;
        else    begin
                if(value > 0) // could be V_MID or V_SAT_P
                    return (value > clamp_val) ? V_SAT_P : V_MID;
                else // could be V_MMID or V_SAT_M
                    return (value < -clamp_val) ? V_SAT_M : V_MMID;
        end

    endfunction

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_values = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(int)::get(this,"","CLAMP_VAL",clamp_val))
            `uvm_fatal("NOCFG","Could not find clamp_val configuration");
        assert(clamp_val >= 4 && clamp_val < INT_MAX-1) else begin// ensure value_category_e can hit each enum
        if(clamp_val >= INT_MAX-1)
            `uvm_warning("ASTERR","Due to CLAMP_VAL being too large, not all coverage points will be hit")
        else
            `uvm_warning("ASTERR","Due to CLAMP_VAL being too small, not all coverage points will be hit")
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COVERAGE",$sformatf("\t\tCoverage: %0.2f%%\n",cg_values.get_inst_coverage()),UVM_NONE)
    endfunction

    virtual function void write(clamp_transaction clampt);
        value_c = classify_value(clampt.value);
        cg_values.sample();
    endfunction

endclass