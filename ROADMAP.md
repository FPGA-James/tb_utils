# tb_utils Roadmap

A VHDL-2008 testbench utilities library. Simulator-agnostic (pure VHDL). Bus widths inferred at call site via unconstrained formals.

## Phase 1 — Foundation + AXI (current)
- `tb_pkg` — `clk_gen`, `reset_seq`, `print` (INFO/WARNING/ERROR/FATAL + sim timestamp)
- `tb_assert_pkg` — `check_equal`, `check_true`, `check_stable`
- `tb_scoreboard_pkg` — queue-based scoreboard protected type
- `axis_pkg` — AXI-Stream: `axis_write`, `axis_read`, `axis_monitor`
- `axi_lite_pkg` — AXI-Lite: `axi_lite_write`, `axi_lite_read`, `axi_lite_monitor`
- Self-test testbenches, GHDL Makefile

## Phase 2 — AXI4 Full + Memory Model
- `axi4_pkg` — burst `axi4_write`, `axi4_read`, `axi4_monitor`
- `mem_model/axi4_mem.vhd` — generic AXI4 slave RAM
- `mem_model/axi_lite_mem.vhd` — generic AXI-Lite slave RAM

## Phase 3 — File I/O
- `tb_file_pkg` — `read_hex_file`, `write_hex_file`, `read_csv`, `write_csv`
- Enable data-heavy tests using stimulus files and golden reference comparison

## Phase 4 — Serial Protocols
- `uart_pkg` — `uart_tx`, `uart_rx` (configurable baud, data bits, parity)
- `spi_pkg` — `spi_write`, `spi_read` (mode 0/1/2/3, configurable CPOL/CPHA)
- `i2c_pkg` — `i2c_write`, `i2c_read` (7-bit addressing, clock stretching)

## Phase 5 — Alternative Bus Protocols
- `avalon_pkg` — Avalon-MM `avalon_write`, `avalon_read`, `avalon_monitor`
- `wishbone_pkg` — Wishbone classic `wb_write`, `wb_read`, `wb_monitor`
