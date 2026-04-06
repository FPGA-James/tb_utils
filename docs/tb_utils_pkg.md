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
    constant active_level : in  std_logic := '1';
    constant duration     : in  time      := 100 ns
);
```

Asserts `rst` to `active_level` for `duration`, then deasserts it. A `wait for 0 ns` after deassertion ensures the signal propagates before the calling process continues.

**Limitations**
- Blocking — the calling process stalls for `duration`.
- Does not wait for a clock edge; add `wait until rising_edge(clk)` before/after if synchronous reset alignment is needed.

**Example**

```vhdl
-- Active-high reset for 50 ns
reset_seq(rst, active_level => '1', duration => 50 ns);

-- Active-low reset with defaults (active_level='1', duration=100 ns)
reset_seq(rst_n, active_level => '0');
```
