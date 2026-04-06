# coverage_pkg

Functional coverage collector. Tracks how many times stimulus has hit defined bins, reports coverage percentage, identifies uncovered bins, and provides coverage-directed random generation via `rand_cov_point`.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/coverage_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

Declare as a shared variable:

```vhdl
shared variable cov : t_coverage;
```

Coverage is collected in two independent dimensions:

- **1D bins** — ranges of a single integer value
- **Cross bins** — ranges over a 2D grid of (value1, value2) pairs

Both dimensions are tracked in the same object. Coverage percentage is reported separately for each.

---

## 1D Coverage

### `set_name`

```vhdl
procedure set_name(name : in string);
```

Sets a display name shown in coverage reports. Call before adding bins.

**Example**

```vhdl
cov.set_name("addr_cov");
```

---

### `add_bin`

```vhdl
procedure add_bin(name : in string; min : in integer; max : in integer);
procedure add_bin(name : in string; min : in integer; max : in integer; weight : in positive);
```

Adds a named bin covering the integer range `[min, max]` inclusive. `weight` sets the number of hits required for the bin to count as covered (default 1). Use `weight > 1` when a stimulus must be seen multiple times (e.g., both a write and a read to the same address).

**Limitations**
- Maximum of 64 bins per coverage object (compile-time constant in the package).
- Bins are not checked for overlap — overlapping ranges will each be sampled independently.

**Example**

```vhdl
-- Each register must be written AND read (weight=2)
addr_cov.add_bin("reg0", 0, 0, 2);
addr_cov.add_bin("reg1", 1, 1, 2);

-- Data quadrants (weight=1)
data_cov.add_bin("low",  0,   63);
data_cov.add_bin("mid",  64, 191);
data_cov.add_bin("high", 192, 254);
```

---

### `add_illegal_bin`

```vhdl
procedure add_illegal_bin(name : in string; min : in integer; max : in integer);
```

Adds a bin for values that must never occur. If `sample` hits an illegal bin, an `[error]` is logged. Illegal bins are excluded from the coverage percentage and shown separately in `report_coverage`.

**Example**

```vhdl
data_cov.add_illegal_bin("reserved", 255, 255);
```

---

### `sample`

```vhdl
procedure sample(value : in integer);
```

Records a hit for every normal bin whose range includes `value`. Fires an `[error]` if `value` falls in an illegal bin.

**Example**

```vhdl
data_cov.sample(hbyte);     -- sample the high byte of write data
addr_cov.sample(widx);      -- sample the register index
txn_cov.sample(0);          -- 0=write, 1=read
```

---

### `get_coverage`

```vhdl
impure function get_coverage return real;
```

Returns the 1D coverage percentage as a `real` in the range `[0.0, 100.0]`. A bin is "covered" when its `hits >= weight`. Illegal bins are excluded.

**Example**

```vhdl
print(INFO, "coverage: " & real'image(cov.get_coverage) & "%");
```

---

### `is_covered`

```vhdl
impure function is_covered return boolean;
```

Returns `true` when `get_coverage = 100.0` (all non-illegal bins have met their weight targets). Use in loop termination conditions.

**Example**

```vhdl
while not addr_cov.is_covered or not data_cov.is_covered loop
    -- generate more stimulus
end loop;
```

---

### `get_uncovered`

```vhdl
impure function get_uncovered return string;
```

Returns a comma-separated list of bin names that have not yet reached their weight target. Returns `"none"` if fully covered. Useful for mid-run progress messages.

**Example**

```vhdl
print(INFO, "still uncovered: " & data_cov.get_uncovered);
-- e.g. "mid, high"
```

---

### `reset`

```vhdl
procedure reset;
```

Clears all hit counts back to zero while keeping the bin definitions intact. Useful for re-running coverage across multiple test phases.

**Example**

```vhdl
cov.reset;
-- run phase 2 stimulus
```

---

### `rand_cov_point`

```vhdl
impure function rand_cov_point(
    bin_ticket : integer;
    pos_ticket : integer
) return integer;
```

Coverage-directed random value generation. Selects a bin with probability proportional to its remaining hits needed (`weight - hits`), then returns a random value within that bin's range.

- `bin_ticket` — a random integer used to select the bin (use `rng.rand_int(0, 999)`)
- `pos_ticket` — a random integer used to select the position within the bin (use `rng.rand_int(lo, hi)` matching the bin's range)

When all bins are fully covered, returns a value from the first non-illegal bin.

**Limitations**
- Callers must supply external random integers rather than a `rand_t` reference (avoids cross-package protected type coupling).
- Selection uses `mod`, so very non-uniform bin widths may slightly bias bin selection.

**Example**

```vhdl
-- Target the least-covered register
widx := addr_cov.rand_cov_point(rng.rand_int(0, 999), rng.rand_int(0, 3));

-- Target an uncovered data quadrant
hbyte := data_cov.rand_cov_point(rng.rand_int(0, 999), rng.rand_int(0, 254));
```

---

### `report_coverage`

```vhdl
procedure report_coverage;
```

Prints a formatted coverage report to stdout showing all bins, their hit counts, targets, and covered status. Illegal bins are shown in a separate section.

```
[coverage.report] =================================================================
[coverage.report]   Functional Coverage Report: data_cov
[coverage.report] =================================================================
[coverage.report]   1D Bins:
[coverage.report]   [0] low   range=[1..63]   hits=4  target=1  covered=true
[coverage.report]   [1] mid   range=[64..191] hits=1  target=1  covered=true
[coverage.report]   [2] high  range=[192..254] hits=1  target=1  covered=true
[coverage.report]   1D Coverage   : 100.0%
[coverage.report]   Illegal Bins (0 hits expected):
[coverage.report]   [3] all_ones  range=[255..255]  hits=0  OK
[coverage.report] =================================================================
```

---

## 2D Cross Coverage

### `add_cross_bin`

```vhdl
procedure add_cross_bin(name : in string; min1, max1, min2, max2 : in integer);
procedure add_cross_bin(name : in string; min1, max1, min2, max2 : in integer; weight : in positive);
```

Adds a cross-coverage bin covering the region `[min1, max1] × [min2, max2]`.

**Example**

```vhdl
cov.add_cross_bin("lo_x_lo", 0, 63,  0, 63);
cov.add_cross_bin("lo_x_hi", 0, 63,  64, 127);
cov.add_cross_bin("hi_x_lo", 64, 127, 0, 63);
cov.add_cross_bin("hi_x_hi", 64, 127, 64, 127);
```

---

### `sample_cross`

```vhdl
procedure sample_cross(v1 : in integer; v2 : in integer);
```

Records a hit for any cross bin whose region contains `(v1, v2)`. Skips if either value falls in an illegal 1D bin.

**Example**

```vhdl
cov.sample_cross(addr_idx, data_byte);
```

---

### `get_cross_coverage`

```vhdl
impure function get_cross_coverage return real;
```

Returns the cross-coverage percentage as a `real` in `[0.0, 100.0]`.

---

## Full CRV Example

```vhdl
shared variable rng      : rand_t;
shared variable addr_cov : t_coverage;
shared variable data_cov : t_coverage;

-- Setup
addr_cov.set_name("addr_cov");
addr_cov.add_bin("reg0", 0, 0, 2);   -- weight=2: needs write + read
addr_cov.add_bin("reg1", 1, 1, 2);
addr_cov.add_bin("reg2", 2, 2, 2);
addr_cov.add_bin("reg3", 3, 3, 2);

data_cov.set_name("data_cov");
data_cov.add_bin("zero", 0,   0);
data_cov.add_bin("low",  1,  63);
data_cov.add_bin("mid",  64, 191);
data_cov.add_bin("high", 192, 254);
data_cov.add_illegal_bin("all_ones", 255, 255);

rng.seed(42, 7);

-- CRV loop
while not addr_cov.is_covered or not data_cov.is_covered loop
    widx  := addr_cov.rand_cov_point(rng.rand_int(0, 999), rng.rand_int(0, 3));
    hbyte := data_cov.rand_cov_point(rng.rand_int(0, 999), rng.rand_int(0, 254));
    -- issue write to widx with high byte hbyte ...
    addr_cov.sample(widx);
    data_cov.sample(hbyte);
end loop;

addr_cov.report_coverage;
data_cov.report_coverage;
```
