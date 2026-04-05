# VHDL Functional Coverage Package

A self-contained functional coverage library for VHDL testbenches with no external dependencies (no OSVVM, no third-party libraries).

## Features

- **Named bins** with configurable value ranges
- **Weighted bins** — per-bin hit targets, not just hit-once semantics
- **Per-bin hit counts** — inspect how heavily each range was exercised
- **Cross-coverage** — 2D matrix tracking which (bin_a × bin_b) pairs were exercised
- **Dual reporting** — simulator console via `report` statements + plain-text file via `std.textio`
- **Directed-random stimulus pattern** — loop until coverage goals are met

## Requirements

- VHDL-2008 (uses `std.env.stop`, protected types, `file_open_status`)
- Any standards-compliant simulator (GHDL, ModelSim, Questa, Vivado xsim)

## Files

```
coverage_pkg/
├── README.md                  This file
├── coverage_pkg.vhd           Coverage package (source)
└── tb_coverage_example.vhd    Example testbench showing all features
```

## Quick Start

### 1. Compile

```bash
# GHDL example
ghdl -a --std=08 coverage_pkg.vhd
ghdl -a --std=08 tb_coverage_example.vhd
ghdl -e --std=08 tb_coverage_example
ghdl -r --std=08 tb_coverage_example
```

```tcl
# ModelSim / Questa example
vcom -2008 coverage_pkg.vhd
vcom -2008 tb_coverage_example.vhd
vsim tb_coverage_example
run -all
```

### 2. Instantiate in your testbench

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use work.coverage_pkg.all;

architecture sim of tb_my_dut is
    shared variable cov : t_coverage;
begin
    stimulus : process
    begin
        -- Define bins (do this once, before sampling)
        cov.add_bin("zero",   0,   0,  weight => 5);
        cov.add_bin("low",    1,  63,  weight => 2);
        cov.add_bin("high",  64, 254,  weight => 2);
        cov.add_bin("max",  255, 255,  weight => 5);

        -- Sample during stimulus
        cov.sample(to_integer(unsigned(dut_output)));

        -- Sample cross-coverage for two signals
        cov.sample_cross(to_integer(unsigned(sig_a)),
                         to_integer(unsigned(sig_b)));

        -- Report at end of simulation
        cov.report_all("my_coverage.txt");
        std.env.stop;
    end process;
end architecture;
```

## API Reference

### `add_bin(name, min, max [, weight])`

Defines a coverage bin.

| Parameter | Type       | Description                                      |
|-----------|------------|--------------------------------------------------|
| `name`    | `string`   | Human-readable label (truncated to 32 chars)     |
| `min`     | `integer`  | Inclusive lower bound of the bin's value range   |
| `max`     | `integer`  | Inclusive upper bound of the bin's value range   |
| `weight`  | `positive` | Hit count required to mark bin as covered (default: `1`) |

Bins are checked in definition order; the first matching bin wins. Overlapping ranges are allowed but not recommended.

---

### `sample(value)`

Looks up `value` against the defined bins and increments the matching bin's hit counter.

---

### `sample_cross(val_a, val_b)`

Resolves both values to their bin indices and increments the corresponding cell in the cross-coverage matrix.  Both values share the same bin definitions.

---

### `get_coverage` → `real`

Returns the percentage of bins whose hit count has reached their `weight` target.

```
covered_bins / total_bins × 100.0
```

---

### `get_cross_coverage` → `real`

Returns the percentage of cross-coverage matrix cells that have at least one hit.

```
non_zero_cells / (bin_count × bin_count) × 100.0
```

---

### `get_bin_count` → `integer`

Returns the number of bins currently defined.

---

### `report_coverage`

Prints the full report to the simulator console using VHDL `report` statements.

---

### `write_coverage_file(filename)`

Writes the full report to a plain-text file. The file is created (or overwritten) at the path given. The path is relative to the simulator working directory.

---

### `report_all(filename)`

Calls both `report_coverage` and `write_coverage_file` in one step.

## Coverage Report Format

```
=================================================================
  Functional Coverage Report
=================================================================
  1D Bins
  -------
  Idx  Name                              Range            Hits   Target  OK?
  ---  --------------------------------  ---------------  -----  ------  ---
    0  zero                              [     0..     0]      5       5  YES
    1  low                               [     1..    63]     42       2  YES
    2  high                              [    64..   254]     38       2  YES
    3  max                               [   255..   255]      5       5  YES

  1D Coverage : 1.00000E+02 %

  Cross-Coverage Matrix  (rows = val_a bin, cols = val_b bin)
         0     1     2     3
  ---  ----  ----  ----  ----
    0     3     8    11     2
    1     9    21    19     7
    2    12    18    20     6
    3     2     6     5     3

  Cross Coverage : 1.00000E+02 %
=================================================================
```

## Tuning Constants

At the top of `coverage_pkg.vhd`:

```vhdl
constant MAX_BINS     : integer := 32;   -- maximum number of bins
constant MAX_NAME_LEN : integer := 32;   -- maximum bin name length (chars)
```

Increase `MAX_BINS` if you need more bins. The cross-coverage matrix is `MAX_BINS × MAX_BINS` so memory scales quadratically — keep it reasonable for simulation.

## Limitations

- Bin ranges are checked linearly; the first matching bin wins. For best results define non-overlapping bins.
- Cross-coverage uses the same bin set for both axes. Separate bin sets for two different signal types would require two `t_coverage` instances and a manual cross-sample wrapper.
- `real'image` output format is simulator-dependent (typically scientific notation). For prettier percentages, replace `fmt_pct` in the package body with your preferred formatting function.

## Licence

Public domain — use freely in any project, commercial or otherwise.
