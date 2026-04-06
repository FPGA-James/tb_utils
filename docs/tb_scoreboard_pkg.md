# tb_scoreboard_pkg

Queue-based scoreboard for DUT output verification. The testbench pushes expected values on the stimulus side; the monitor or receiver side calls `check` with the actual value. Mismatches and queue errors are logged as `[error]`.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/tb_scoreboard_pkg.vhd` |
| Depends on | `tb_utils_pkg`, `tb_assert_pkg` |
| VHDL standard | 2008 |

The scoreboard uses a singly-linked list internally (heap-allocated `access` type), so the queue depth is limited only by simulator memory. Each node stores up to 256 bits; for wider buses, widen the `slv_node_t.data` field.

---

## Types

### `scoreboard_t`

```vhdl
shared variable sb : scoreboard_t;
```

Declare as a shared variable so it is accessible from multiple concurrent processes (stimulus and monitor).

---

## Methods

### `push`

```vhdl
procedure push(constant data : in std_logic_vector);
```

Enqueues the expected value at the tail of the queue. Call this from the stimulus process immediately before or at the same simulation time as the corresponding DUT transaction is initiated.

**Limitations**
- Maximum data width is 256 bits (field `data : std_logic_vector(255 downto 0)` in the node type). Widen if needed.

**Example**

```vhdl
sb.push(x"DEADBEEF");
axi_lite_write(..., x"DEADBEEF");
```

---

### `check`

```vhdl
procedure check(
    constant actual : in std_logic_vector;
    constant msg    : in string := ""
);
```

Dequeues the head of the queue and compares it to `actual`. Logs PASS (DEBUG) or FAIL (ERROR). If the queue is empty when `check` is called, logs an error ("queue empty, unexpected data").

**Example**

```vhdl
axi_lite_read(..., rd_data);
sb.check(rd_data, "reg 0 read-back");
```

---

### `final_report`

```vhdl
procedure final_report;
```

Prints a summary of total passes, failures, and any items left unchecked in the queue. Call once at end of simulation.

```
[scoreboard] === Scoreboard Final Report ===
[scoreboard]   PASS: 4
[scoreboard]   FAIL: 0
[scoreboard]   Result: ALL PASS
```

**Limitations**
- Does not stop the simulation on failure. Follow with `check_equal(sb.fail_count, 0, ...)` if a hard fail is needed.

---

### `pass_count` / `fail_count` / `depth`

```vhdl
impure function pass_count return natural;
impure function fail_count return natural;
impure function depth      return natural;
```

Query the running totals. `depth` returns the number of items currently in the queue (should be 0 after all checks complete).

**Example**

```vhdl
sb.final_report;
check_equal(sb.fail_count, 0, "no scoreboard failures");
```

---

## Full Example

```vhdl
shared variable sb : scoreboard_t;

-- Stimulus process
for i in 0 to 3 loop
    sb.push(expected_data(i));
    axis_write(clk, tvalid, tready, tdata, tlast, expected_data(i));
end loop;

-- Monitor / receiver process
for i in 0 to 3 loop
    axis_read(clk, tvalid, tready, tdata, tlast, rx, rx_last);
    sb.check(rx, "beat " & integer'image(i));
end loop;

sb.final_report;
check_equal(sb.fail_count, 0, "no failures");
std.env.stop;
```
