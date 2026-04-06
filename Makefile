# tb_utils Makefile — requires GHDL on PATH
SHELL        := bash
.SHELLFLAGS  := -o pipefail -c

GHDL      := ghdl
GHDLFLAGS := --std=08
LIB       := tb_utils
WORKDIR   := work

SRC := \
  src/tb_utils_pkg.vhd \
  src/tb_file_pkg.vhd \
  src/tb_assert_pkg.vhd \
  src/tb_scoreboard_pkg.vhd \
  src/axis_pkg.vhd \
  src/axi_lite_pkg.vhd \
  src/coverage_pkg.vhd \
  src/prng_pkg.vhd \
  src/flow_ctrl_pkg.vhd \
  src/sequence_pkg.vhd

TBS := \
  tb/tb_core_tb.vhd \
  tb/axis_tb.vhd \
  tb/axi_lite_tb.vhd \
  tb/coverage_tb.vhd \
  tb/random_tb.vhd \
  tb/crv_axi_lite_tb.vhd \
  tb/file_tb.vhd

TB_TOPS := tb_core_tb axis_tb axi_lite_tb coverage_tb random_tb crv_axi_lite_tb file_tb

.PHONY: all compile test run clean

all: test

compile: $(WORKDIR)/.compiled

$(WORKDIR)/.compiled: $(SRC) $(TBS)
	mkdir -p $(WORKDIR)
	$(GHDL) -i $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $(SRC)
	$(GHDL) -i $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $(TBS)
	@for tb in $(TB_TOPS); do \
	  $(GHDL) -m $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) -o $(WORKDIR)/$$tb $$tb; \
	done
	touch $@

# Run all testbenches; output shown on terminal and saved to work/<tb>.log
# Waveforms saved to work/<tb>.ghw (open with GTKWave)
test: compile
	@for tb in $(TB_TOPS); do \
	  echo "--- Running $$tb ---"; \
	  $(WORKDIR)/$$tb --wave=$(WORKDIR)/$$tb.ghw 2>&1 | tee $(WORKDIR)/$$tb.log || exit 1; \
	done
	@echo "=== All tests passed ==="

# Run a single testbench: make run TB=axis_tb
# Output shown on terminal and saved to work/<TB>.log
# Waveform saved to work/<TB>.ghw (open with GTKWave)
run: compile
	$(WORKDIR)/$(TB) --wave=$(WORKDIR)/$(TB).ghw 2>&1 | tee $(WORKDIR)/$(TB).log

clean:
	rm -rf $(WORKDIR)
	rm -f $(TB_TOPS)
