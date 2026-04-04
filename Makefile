# tb_utils Makefile — requires GHDL on PATH
GHDL      := ghdl
GHDLFLAGS := --std=08
LIB       := tb_utils
WORKDIR   := work

SRC := \
  src/tb_pkg.vhd \
  src/tb_assert_pkg.vhd \
  src/tb_scoreboard_pkg.vhd \
  src/axis_pkg.vhd \
  src/axi_lite_pkg.vhd \
  src/coverage_pkg.vhd

TBS := \
  tb/tb_core_tb.vhd \
  tb/axis_tb.vhd \
  tb/axi_lite_tb.vhd

TB_TOPS := tb_core_tb axis_tb axi_lite_tb

.PHONY: all compile test run clean

all: test

compile: $(WORKDIR)/.compiled

$(WORKDIR)/.compiled: $(SRC) $(TBS)
	mkdir -p $(WORKDIR)
	$(GHDL) -i $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $(SRC)
	$(GHDL) -i $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $(TBS)
	@for tb in $(TB_TOPS); do \
	  $(GHDL) -m $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $$tb; \
	done
	touch $@

test: compile
	@for tb in $(TB_TOPS); do \
	  echo "--- Running $$tb ---"; \
	  $(GHDL) -r $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $$tb || exit 1; \
	done
	@echo "=== All tests passed ==="

# Run a single testbench: make run TB=axis_tb
run: compile
	$(GHDL) -r $(GHDLFLAGS) --work=$(LIB) --workdir=$(WORKDIR) $(TB)

clean:
	rm -rf $(WORKDIR)
