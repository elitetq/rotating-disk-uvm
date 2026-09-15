# xsim batch script, used only when WAVES=1 (Makefile passes -tclbatch waves.tcl).
# xsim sources this before time 0, so logging is armed from the very first edge.

log_wave -recursive *  ;# record every signal in the top scope and all scopes below it into the -wdb file
run all                ;# advance simulation until $finish (UVM calls it after the report phase)
quit                   ;# exit xsim so make gets its exit status back instead of sitting at the Tcl prompt
