# tb_assert_pkg

Lightweight assertion procedures for checking signal and variable values in simulation. All failures print an `[error]` tagged line but do not stop the simulation — use `print(FATAL, ...)` or check `fail_count` at the end if a hard stop is needed.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/tb_assert_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

---

## Procedures

### `check_equal` — `std_logic_vector`

```vhdl
procedure check_equal(
    constant actual   : in std_logic_vector;
    constant expected : in std_logic_vector;
    constant msg      : in string := ""
);
```

Compares two `std_logic_vector` values. On failure prints both values in hexadecimal.

**Limitations**
- Widths must match; GHDL will error at elaboration if they differ.
- `msg` is appended to the log line — keep it short and descriptive.

**Example**

```vhdl
check_equal(rdata, x"DEADBEEF", "read-back reg 0");
```

---

### `check_equal` — `integer`

```vhdl
procedure check_equal(
    constant actual   : in integer;
    constant expected : in integer;
    constant msg      : in string := ""
);
```

**Example**

```vhdl
check_equal(sb.fail_count, 0, "no scoreboard failures");
check_equal(pkt_count, 16, "all packets received");
```

---

### `check_equal` — `std_logic`

```vhdl
procedure check_equal(
    constant actual   : in std_logic;
    constant expected : in std_logic;
    constant msg      : in string := ""
);
```

**Example**

```vhdl
check_equal(rst, '0', "reset deasserted");
check_equal(tlast, '1', "last beat flagged");
```

---

### `check_true`

```vhdl
procedure check_true(
    constant condition : in boolean;
    constant msg       : in string := ""
);
```

Fails if `condition` is `false`. Use for anything that doesn't fit the equality overloads — comparisons, range checks, coverage closure, etc.

**Example**

```vhdl
check_true(addr_cov.is_covered, "all addresses covered");
check_true(now < 3 ms,          "simulation finished within time budget");
check_true(rx_last = true,      "tlast set on final beat");
```

---

### `check_stable`

```vhdl
procedure check_stable(
    signal   sig      : in std_logic_vector;
    constant duration : in time;
    constant msg      : in string := ""
);
```

Samples `sig` at the call site, then waits `duration` in 1 ns steps, checking that `sig` does not change. Reports the simulation time of the first change if it occurs.

**Limitations**
- Blocking — stalls the calling process for `duration`.
- Sampling resolution is fixed at 1 ns; glitches shorter than 1 ns will be missed.
- Only works with `std_logic_vector`; no `std_logic` overload.
- Must be called from a process (not a subprogram that itself has no process context).

**Example**

```vhdl
-- Verify output bus holds stable for one full clock period after valid de-asserts
check_stable(wdata, 10 ns, "wdata stable during hold time");
```
