# -----------------------------------------------------------------------------
# Makefile mínimo para compilar y correr con Synopsys VCS + UVM 1.2
#
#   make                       compila y corre uart_base_test con semilla 1 y el caso base
#   make run SEED=42           corre otra semilla (sin recompilar)
#   make run CASE=x            corre con los plusargs de args/x.args (un archivo por caso)
#   make run ARGS="+UART_SW_ITER=5"   agrega plusargs sueltos encima del caso
#   make regress CASE=x SEEDS=20      corre las semillas 1 a SEEDS y dice cuantas pasaron
#   make regress_all SEEDS=5         corre todos los casos (CASES) y muestra un resumen
#   make BUS8=1                compila la variante de bus de 8 bits
#   make cov                   fusiona la cobertura y genera el reporte HTML
#   make verdi                 abre Verdi con la base de datos de compilación
# -----------------------------------------------------------------------------

TEST  ?= uart_base_test
SEED  ?= 1
CASE  ?= base
SEEDS ?= 20
CASES ?= base errores loopback interrupciones overrun modem modem_loop linea reset
ARGS  ?=
BUS8  ?= 0
FSDB  ?= 0

DEFINES :=
ifeq ($(BUS8),1)
  DEFINES += +define+DATA_BUS_WIDTH_8
endif
ifeq ($(FSDB),1)
  DEFINES += +define+DUMP_FSDB
endif

COV_TYPES := line+cond+fsm+branch+tgl

VCS_OPTS := -full64 -sverilog -ntb_opts uvm-1.2 \
            -timescale=1ns/1ps \
            -debug_access+all -kdb \
            -cm $(COV_TYPES) -cm_hier cov_hier.cfg \
            $(DEFINES) \
            -f filelist.f \
            -top tb_top \
            -l comp.log

# ARGS va ANTES del archivo del caso: $value$plusargs se queda con el primero que encuentra,
# asi un plusarg suelto en ARGS le gana al mismo plusarg del archivo (ej. ARGS="+UART_SW_ITER=5")
SIMV_OPTS := +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) \
             -cm $(COV_TYPES) -cm_name $(CASE)_$(SEED) \
             +UVM_VERBOSITY=UVM_LOW \
             $(ARGS) -f args/$(CASE).args \
             -l run_$(CASE)_$(SEED).log

.PHONY: all comp run regress regress_all cov verdi clean

all: comp run

comp: cov_hier.cfg
	vcs $(VCS_OPTS)

run:
	@test -f args/$(CASE).args || (echo "No existe args/$(CASE).args" && exit 1)
	./simv $(SIMV_OPTS)

# Corre las semillas 1 a SEEDS del mismo caso y al final dice cuales fallaron
# una semilla pasa si su log termina con 0 UVM_ERROR y 0 UVM_FATAL
regress:
	@for s in $$(seq 1 $(SEEDS)); do $(MAKE) --no-print-directory run CASE=$(CASE) SEED=$$s || true; done
	@pass=0; fail=0; \
	for s in $$(seq 1 $(SEEDS)); do \
	  log=run_$(CASE)_$$s.log; \
	  if grep -qE "UVM_ERROR +: +0" $$log && grep -qE "UVM_FATAL +: +0" $$log; then \
	    pass=$$((pass+1)); \
	  else \
	    fail=$$((fail+1)); echo "FALLO: $$log"; \
	  fi; \
	done; \
	echo "== $(CASE): $$pass pasaron, $$fail fallaron de $(SEEDS) =="

# Corre cada caso con las mismas semillas y guarda solo su ultima linea, que es el resumen
regress_all:
	@# Vaciamos el resumen anterior para no mezclar corridas
	@: > regress_resumen.txt
	@# Cada regress corre sus semillas, tail guarda su resumen al final del archivo
	@for c in $(CASES); do \
	  $(MAKE) --no-print-directory regress CASE=$$c SEEDS=$(SEEDS) | tail -n 1 >> regress_resumen.txt; \
	done
	@# Mostramos juntos los resultados de todos los casos
	@cat regress_resumen.txt

# Solo el DUT cuenta para la cobertura de código.
cov_hier.cfg:
	echo "+tree tb_top.dut" > $@

cov:
	urg -full64 -dir simv.vdb -dbname merged -report cov_report -format both

verdi:
	verdi -dbdir simv.daidir -ssf waves.fsdb &

clean:
	rm -rf simv simv.daidir simv.vdb csrc ucli.key vc_hdrs.h \
	       *.log *.fsdb cov_report merged.vdb cov_hier.cfg \
	       novas* verdiLog AN.DB
