XILINX_ROOT   ?= $(HOME)/Vivado/2025.2
XILINX_VIVADO ?= $(XILINX_ROOT)/Vivado
BIN           := $(XILINX_VIVADO)/bin

XVLOG := $(BIN)/xvlog
XELAB := $(BIN)/xelab
XSIM  := $(BIN)/xsim
XCRG  := $(BIN)/xcrg

# Knobs
PHASE     ?= pwm
TEST      ?= $(PHASE)_smoke_test
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
WAVES     ?= 0
COV       ?= 0
TIMEOUT   ?= 20ms

TOP   := tb_$(PHASE)_top
SNAP  := $(PHASE)_snap
FLIST := filelists/$(PHASE).f
LOGS  := logs

# Flags
XVLOG_FLAGS := -sv -L uvm --incr
XELAB_FLAGS := -L uvm --relax -timescale 1ns/1ps -s $(SNAP)
XSIM_FLAGS  := -runall -sv_seed $(SEED) \
               -testplusarg "UVM_TESTNAME=$(TEST)" \
               -testplusarg "UVM_VERBOSITY=$(VERBOSITY)" \
               -testplusarg "UVM_TIMEOUT=$(TIMEOUT)"

ifeq ($(WAVES),1)
  XELAB_FLAGS += -debug typical
  XSIM_FLAGS  := -tclbatch waves.tcl -wdb $(LOGS)/$(PHASE)_$(TEST)_$(SEED).wdb \
                 -sv_seed $(SEED) \
                 -testplusarg "UVM_TESTNAME=$(TEST)" \
                 -testplusarg "UVM_VERBOSITY=$(VERBOSITY)" \
                 -testplusarg "UVM_TIMEOUT=$(TIMEOUT)"
endif

ifeq ($(COV),1)
  XSIM_FLAGS += -cov_db_dir ./xsim.covdb -cov_db_name $(PHASE)_$(TEST)_$(SEED)
endif

.PHONY: all compile elab run gui cov clean veryclean help

all: run

$(LOGS):
	@mkdir -p $(LOGS)

compile: | $(LOGS)
	$(XVLOG) $(XVLOG_FLAGS) -f $(FLIST) -log $(LOGS)/xvlog.$(PHASE).log

elab: compile
	$(XELAB) $(XELAB_FLAGS) $(TOP) -log $(LOGS)/xelab.$(PHASE).log

run: elab
	$(XSIM) $(SNAP) $(XSIM_FLAGS) -log $(LOGS)/$(PHASE).$(TEST).$(SEED).log

gui: WAVES=1
gui: elab
	$(XSIM) $(SNAP) -gui \
	  -testplusarg "UVM_TESTNAME=$(TEST)" \
	  -testplusarg "UVM_VERBOSITY=$(VERBOSITY)"

# Merge whatever coverage databases exist into an HTML report.
# Flags vary between Vivado releases — run `$(XCRG) -help` and fix these once.
cov:
	$(XCRG) -dir ./xsim.covdb -report_format html -report_dir ./cov_report

clean:
	rm -rf xsim.dir $(LOGS) *.jou *.pb *.wdb .Xil webtalk*

veryclean: clean
	rm -rf xsim.covdb cov_report run

help:
	@echo "PHASE     = pwm | clamp | quad | ctrl      (default: pwm)"
	@echo "TEST      = UVM test class name           (default: <PHASE>_smoke_test)"
	@echo "SEED      = integer                       (default: 1)"
	@echo "VERBOSITY = UVM_LOW|UVM_MEDIUM|UVM_HIGH|UVM_DEBUG"
	@echo "WAVES     = 0 | 1                         dump a .wdb"
	@echo "COV       = 0 | 1                         collect coverage"