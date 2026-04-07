# tb_scoreboard_pkg

Queue-based scoreboard for DUT output verification. The testbench pushes expected values on the stimulus side; the monitor or receiver side calls `check` with the actual value. Supports `std_logic_vector`, `integer`, `std_logic`, and `string`. Mismatches and queue errors are logged as `[error]`.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/tb_scoreboard_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

Expected values are serialised to strings internally. The queue is a singly-linked list (heap-allocated), so depth is limited only by simulator memory.

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
procedure push(constant data : in integer);
procedure push(constant data : in std_logic);
procedure push(constant data : in string);
```

Enqueues the expected value at the tail of the queue. Call from the stimulus process before or at the same simulation time as the corresponding DUT transaction.

> **Note:** When passing bit-string or string literals, a type mark is required to resolve overload ambiguity:
> ```vhdl
> sb.push(std_logic_vector'(x"AA"));   -- not sb.push(x"AA")
> sb.push(string'("hello"));           -- not sb.push("hello")
> sb.push(42);                         -- integer: unambiguous
> sb.push('1');                        -- std_logic: unambiguous
> ```

---

### `check`

```vhdl
procedure check(constant actual : in std_logic_vector; constant msg : in string := "");
procedure check(constant actual : in integer;          constant msg : in string := "");
procedure check(constant actual : in std_logic;        constant msg : in string := "");
procedure check(constant actual : in string;           constant msg : in string := "");
```

Dequeues the head of the queue and compares it to `actual`. Logs PASS (DEBUG) or FAIL (ERROR). If the queue is empty, logs "queue empty, unexpected data".

The same type-mark rule applies at call sites for SLV and string literals.

**Example**

```vhdl
-- std_logic_vector
sb.push(std_logic_vector'(x"DEADBEEF"));
sb.check(std_logic_vector'(rx_data), "reg read-back");

-- integer
sb.push(42);
sb.check(seq.next_val, "sequence value");

-- std_logic
sb.push('1');
sb.check(dut_valid, "valid asserted");

-- string
sb.push(string'("OK"));
sb.check(string'(status_msg), "status");
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
- Does not stop the simulation on failure. Follow with `check_equal(sb.fail_count, 0, ...)` if a hard stop is needed.

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
    sb.push(std_logic_vector'(expected_data(i)));
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
