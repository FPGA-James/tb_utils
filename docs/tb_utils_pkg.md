# tb_utils_pkg

Core testbench utilities: logging, clock generation, and reset sequencing. No external dependencies — all other packages in `tb_utils` depend on this one.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/tb_utils_pkg.vhd` |
| Depends on | Nothing |
| VHDL standard | 2008 |

`tb_utils_pkg` provides the three primitives every testbench needs: a structured logger, a clock driver, and a reset driver. Output is written directly to stdout via `std.textio.writeline` — no simulator-specific `$display` or proprietary logging frameworks.

---

## Types

### `log_level_t`

```vhdl
type log_level_t is (DEBUG, INFO, WARNING, ERROR, FATAL);
```

Severity levels used by `print`. Messages are tagged with the level and the current simulation timestamp.

| Level | Behaviour |
|-------|-----------|
| `DEBUG` | Informational, high volume |
| `INFO` | Normal milestones |
| `WARNING` | Non-fatal anomalies |
| `ERROR` | Failures that do not stop simulation |
| `FATAL` | Prints message then calls `report ... severity failure` to stop the simulator |

---

## Procedures

### `print` (with level)

```vhdl
procedure print(
    constant level : in log_level_t;
    constant msg   : in string
);
```

Writes a timestamped, tagged line to stdout:

```
[50000000 fs][info] my message
```

`FATAL` additionally issues a VHDL `failure`, which stops the simulation.

**Example**

```vhdl
print(INFO,    "DUT ready");
print(WARNING, "unexpected response, retrying");
print(ERROR,   "data mismatch at address 0x10");
print(FATAL,   "unrecoverable state — aborting");
```

---

### `print` (INFO shorthand)

```vhdl
procedure print(constant msg : in string);
```

Equivalent to `print(INFO, msg)`.

**Example**

```vhdl
print("axis_tb: starting burst transfer");
```

---

### `clk_gen`

```vhdl
procedure clk_gen(
    signal   clk    : inout std_logic;
    constant period : in    time
);
```

Drives `clk` with the given period. The procedure loops forever — call it inside a dedicated process that is never expected to finish.

**Limitations**
- Must be the only driver on `clk`.
- The process containing `clk_gen` should have no other statements after it.

**Example**

```vhdl
clk_proc : process
begin
    clk_gen(clk, 10 ns);   -- 100 MHz
end process;
```

---

### `reset_seq`

```vhdl
procedure reset_seq(
    signal   rst          : out std_logic;
    signal   clk          : in  std_logic;
    constant active_level : in  std_logic := '1';
    constant cycles       : in  positive  := 8
);
```

Asserts `rst` to `active_level` for `cycles` rising edges of `clk`, then deasserts it. A `wait for 0 ns` after deassertion ensures the signal propagates before the calling process continues.

**Limitations**
- Blocking — the calling process stalls until all clock cycles complete.
- `clk` must already be running (driven by `clk_gen` or similar) before `reset_seq` is called.

**Example**

```vhdl
-- Active-high reset for 5 clock cycles
reset_seq(rst, clk, active_level => '1', cycles => 5);

-- Active-low reset with defaults (active_level='1', cycles=8)
reset_seq(rst_n, clk, active_level => '0');
```
