XILINX_ROOT   ?= $(HOME)/Vivado/2025.2
XILINX_VIVADO ?= $(XILINX_ROOT)/Vivado
BIN           := $(XILINX_VIVADO)/bin

XVLOG := $(BIN)/xvlog
XELAB := $(BIN)/xelab
XSIM  := $(BIN)/xsim
XCRG  := $(BIN)/xcrg

# Knobs
PHASE     ?= pwm
TEST      ?= $(PHASE)_base_test
SEED      ?= 1
VERBOSITY ?= UVM_HIGH
WAVES     ?= 0
COV       ?= 0
TIMEOUT   ?= 20000000 # 20ms
ERROR_CAP ?= 20

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
               -testplusarg "UVM_TIMEOUT=$(TIMEOUT)" \
			   -testplusarg "UVM_MAX_QUIT_COUNT=$(ERROR_CAP)"

ifeq ($(WAVES),1)
  XELAB_FLAGS += -debug typical
  XSIM_FLAGS  := -tclbatch waves.tcl -wdb $(LOGS)/$(PHASE)_$(TEST)_$(SEED).wdb \
                 -sv_seed $(SEED) \
                 -testplusarg "UVM_TESTNAME=$(TEST)" \
                 -testplusarg "UVM_VERBOSITY=$(VERBOSITY)" \
                 -testplusarg "UVM_TIMEOUT=$(TIMEOUT)" \
				 -testplusarg "UVM_MAX_QUIT_COUNT=$(ERROR_CAP)"
endif

ifeq ($(COV),1)
  XSIM_FLAGS += -cov_db_dir . -cov_db_name $(PHASE)_$(TEST)_$(SEED)
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

# Merge every coverage database of PHASE into an HTML report (sim/cov_report/<phase>/functionalCoverageReport/dashboard.html).
# COV_GLOB narrows it to a subset, e.g. COV_GLOB='clamp_clamp_random_test_*'.
# xsim writes xsim.covdb/<name>/ itself, so -cov_db_dir is the directory *above* xsim.covdb.
# The <phase>_snap entry is the design snapshot, not a run, so it is left out.
COV_GLOB ?= $(PHASE)_*
COV_DBS  := $(notdir $(filter-out %_snap,$(wildcard xsim.covdb/$(COV_GLOB))))

cov:
	@test -n "$(COV_DBS)" || { echo "no coverage databases for PHASE=$(PHASE); run with COV=1"; exit 1; }
	$(XCRG) -cov_db_dir . $(addprefix -cov_db_name ,$(COV_DBS)) -report_dir ./cov_report/$(PHASE) -report_format html -log $(LOGS)/xcrg.$(PHASE).log

clean:
	rm -rf xsim.dir $(LOGS) *.jou *.pb *.wdb .Xil webtalk*

veryclean: clean
	rm -rf xsim.covdb cov_report run

help:
	@echo "PHASE     = pwm | clamp                   (default: pwm)"
	@echo "TEST      = UVM test class name           (default: <PHASE>_smoke_test)"
	@echo "SEED      = integer                       (default: 1)"
	@echo "VERBOSITY = UVM_LOW|UVM_MEDIUM|UVM_HIGH|UVM_DEBUG"
	@echo "WAVES     = 0 | 1                         dump a .wdb"
	@echo "COV       = 0 | 1                         collect coverage"