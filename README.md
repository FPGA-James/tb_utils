# tb_utils

A VHDL-2008 testbench utilities library. Simulator-agnostic (pure VHDL, no external dependencies). Bus widths are inferred at the call site via unconstrained formals — no generics or package instantiation needed.

## Packages

| Package | Description |
|---------|-------------|
| [tb_utils_pkg](docs/tb_utils_pkg.md) | Core utilities: logging, clock generation, reset sequencing |
| [tb_file_pkg](docs/tb_file_pkg.md) | File comparison: line-by-line diff with PASS/FAIL reporting |
| [tb_assert_pkg](docs/tb_assert_pkg.md) | Assertion procedures for signal and variable checking |
| [tb_scoreboard_pkg](docs/tb_scoreboard_pkg.md) | Queue-based scoreboard for DUT output verification |
| [axis_pkg](docs/axis_pkg.md) | AXI-Stream BFMs: master write, slave read, passive monitor, file replay/capture (TUSER) |
| [axi_lite_pkg](docs/axi_lite_pkg.md) | AXI-Lite BFMs: master write, master read, passive monitor |
| [coverage_pkg](docs/coverage_pkg.md) | Functional coverage: bins, cross-coverage, directed-random generation |
| [prng_pkg](docs/prng_pkg.md) | Pseudo-random number generator (Wichmann-Hill, repeatable with seed) |
| [sequence_pkg](docs/sequence_pkg.md) | Deterministic stimulus sequences: sweeps, boundary walks, walking-ones |
| [flow_ctrl_pkg](docs/flow_ctrl_pkg.md) | Configurable back-pressure and inter-transaction gap injection |

## Requirements

- VHDL-2008
- [GHDL](https://github.com/ghdl/ghdl) on `PATH` (for the Makefile targets)

Any standards-compliant simulator works (GHDL, ModelSim, Questa, Vivado xsim).

## Quick Start

```bash
# Compile all packages
make compile

# Run all self-test testbenches
make test

# Run a single testbench
make run TB=tb_core_tb

# Clean build artefacts
make clean
```

## Compilation Order

Packages must be compiled in dependency order:

1. [`tb_utils_pkg`](docs/tb_utils_pkg.md) — no dependencies
2. [`tb_file_pkg`](docs/tb_file_pkg.md) — uses `tb_utils_pkg`
3. [`tb_assert_pkg`](docs/tb_assert_pkg.md) — uses `tb_utils_pkg`
4. [`tb_scoreboard_pkg`](docs/tb_scoreboard_pkg.md) — uses `tb_assert_pkg`
5. [`axis_pkg`](docs/axis_pkg.md) — uses `tb_utils_pkg`
6. [`axi_lite_pkg`](docs/axi_lite_pkg.md) — uses `tb_utils_pkg`
7. [`prng_pkg`](docs/prng_pkg.md) — no dependencies
8. [`coverage_pkg`](docs/coverage_pkg.md) — uses `prng_pkg`
9. [`sequence_pkg`](docs/sequence_pkg.md) — no dependencies
10. [`flow_ctrl_pkg`](docs/flow_ctrl_pkg.md) — uses `prng_pkg`

The `Makefile` handles this automatically.

## Repository Layout

```
tb_utils/
├── src/          # Package source files (.vhd)
├── tb/           # Self-test testbenches
├── docs/         # Per-package reference documentation
└── Makefile
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned phases (AXI4 full, serial protocols, Avalon/Wishbone).

## Licence

Public domain — use freely in any project, commercial or otherwise.
