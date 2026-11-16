# -----------------------------------------------------------------------------
# Makefile mínimo para compilar y correr con Synopsys VCS + UVM 1.2
#
#   make                       compila y corre uart_hello_test con semilla 1
#   make run TEST=x SEED=42    corre otra prueba o semilla (sin recompilar)
#   make run PLUSARGS_FILE=plusargs.args
#   make BUS8=1                compila la variante de bus de 8 bits
#   make cov                   fusiona la cobertura y genera el reporte HTML
#   make verdi                 abre Verdi con la base de datos de compilación
# -----------------------------------------------------------------------------

TEST  ?= uart_hello_test
SEED  ?= 1
# Use fresh labels and coverage paths so earlier results cannot masquerade as this batch -- alex
RUN_LABEL ?= $(TEST)_$(SEED)
COV_DIR ?= simv.vdb
# Read the manually edited file on every run -- commented options retain the UVM configuration defaults -- alex
PLUSARGS_FILE ?= plusargs.args
ARGS  ?=
BUS8  ?= 0
FSDB  ?= 0
# Enable the approved baud output extra so its clock can be checked against DL -- alex
BAUD  ?= 1

DEFINES :=
ifeq ($(BAUD),1)
  DEFINES += +define+UART_HAS_BAUDRATE_OUTPUT
endif
ifeq ($(BUS8),1)
  DEFINES += +define+DATA_BUS_WIDTH_8
endif
ifeq ($(FSDB),1)
  DEFINES += +define+DUMP_FSDB
endif

COV_TYPES := line+cond+fsm+branch+tgl

# Compile coverage into the batch-specific database selected by the runner -- alex
#             -cm $(COV_TYPES) -cm_hier cov_hier.cfg
VCS_OPTS := -full64 -sverilog -ntb_opts uvm-1.2 \
            -timescale=1ns/1ps \
            -debug_access+all -kdb \
            -cm $(COV_TYPES) -cm_dir $(COV_DIR) -cm_hier cov_hier.cfg \
            $(DEFINES) \
            -f filelist.f \
            -top tb_top \
            -l comp.log

# Use the same database for simulation and a unique run label for both coverage and the log -- alex
#              -cm $(COV_TYPES) -cm_name $(TEST)_$(SEED)
#              -l run_$(TEST)_$(SEED).log
SIMV_OPTS := +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) \
             -cm $(COV_TYPES) -cm_dir $(COV_DIR) -cm_name $(RUN_LABEL) \
             +UVM_VERBOSITY=UVM_LOW \
             $(ARGS) \
             -l run_$(RUN_LABEL).log

.PHONY: all comp run cov verdi clean

all: comp run

comp: cov_hier.cfg
	vcs $(VCS_OPTS)

run:
# Filter file comments in Bash as in the previous project -- keep simulator controls outside the editable knob file -- alex
# Original direct invocation -- ./simv $(SIMV_OPTS)
	bash run_sim.sh "$(PLUSARGS_FILE)" $(SIMV_OPTS)

# Solo el DUT cuenta para la cobertura de código.
cov_hier.cfg:
	echo "+tree tb_top.dut" > $@

# Merge the database from this batch instead of silently using an older default database -- alex
# urg -full64 -dir simv.vdb -dbname merged -report cov_report -format both
cov:
	urg -full64 -dir $(COV_DIR) -dbname merged -report cov_report -format both

verdi:
	verdi -dbdir simv.daidir -ssf waves.fsdb &

clean:
	rm -rf simv simv.daidir simv.vdb csrc ucli.key vc_hdrs.h \
	       *.log *.fsdb cov_report merged.vdb cov_hier.cfg \
	       novas* verdiLog AN.DB
