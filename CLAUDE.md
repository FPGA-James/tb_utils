# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

`tb_utils` is a VHDL-2008 testbench utilities library. It provides reusable packages for clock/reset generation, logging, assertions, scoreboard checking, and bus-functional models (BFMs) for common protocols (AXI-Stream, AXI-Lite, and more).

## Commands

Requires [GHDL](https://github.com/ghdl/ghdl) on PATH.

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

## Architecture

All library packages live in `src/`. Each package is a single `.vhd` file compiled into the `tb_utils` library. Self-test testbenches in `tb/` use the `tb_utils` library and are standalone — each exercises one or two packages in a loopback or BFM-against-simple-model pattern.

Bus widths are unconstrained in procedure formals (`std_logic_vector` without range); the actual width is inferred from the signal passed at the call site — no generics or package instantiation needed.

Compilation order (dependencies):
1. `tb_pkg` (no deps)
2. `tb_assert_pkg` (uses `tb_pkg` for `print`)
3. `tb_scoreboard_pkg` (uses `tb_assert_pkg`)
4. `axis_pkg` (uses `tb_pkg`)
5. `axi_lite_pkg` (uses `tb_pkg`)
