# flow_ctrl_pkg

Configurable flow controller for injecting realistic back-pressure and inter-transaction gaps into testbenches. Returns a boolean each cycle indicating whether the caller should proceed.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/flow_ctrl_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

Declare as a shared variable:

```vhdl
shared variable fc : t_flow_controller;
```

Each call to `ready_this_cycle` advances the controller's internal state. It is designed to be called once per loop iteration — calling it multiple times per iteration will consume pattern/random state faster than expected.

---

## Modes

| Mode | Behaviour |
|------|-----------|
| `ALWAYS` | Always returns `true` (default) |
| `NEVER` | Always returns `false` |
| `RANDOM` | Returns `true` with probability `throttle %` |
| `THROTTLE` | Same as `RANDOM` — alias for clarity |
| `PATTERN` | Returns `true`/`false` per bit in a 16-bit repeating pattern |

---

## Methods

### `set_mode`

```vhdl
procedure set_mode(m : string);
```

Sets the operating mode. Valid strings: `"ALWAYS"`, `"NEVER"`, `"RANDOM"`, `"PATTERN"`, `"THROTTLE"`. Resets the pattern index to 0.

**Limitations**
- Strings are padded to 8 characters internally; passing an unrecognised string leaves the mode as the padded variant, which falls through to return `true`.

**Example**

```vhdl
fc.set_mode("THROTTLE");
fc.set_mode("PATTERN");
```

---

### `set_throttle`

```vhdl
procedure set_throttle(percent : natural);
```

Sets the probability of `ready_this_cycle` returning `true` for `RANDOM` and `THROTTLE` modes. `100` means always ready; `0` means never ready.

**Example**

```vhdl
fc.set_mode("THROTTLE");
fc.set_throttle(75);   -- ready 75% of cycles
```

---

### `set_pattern`

```vhdl
procedure set_pattern(pat : std_logic_vector);
```

Sets the repeating bit pattern used in `PATTERN` mode. The pattern is up to 16 bits wide; `'1'` bits produce `true`, `'0'` bits produce `false`. The pattern repeats after 16 cycles (or `pat'length` if shorter).

**Limitations**
- Only the low `pat'length` bits of the internal 16-bit register are set; the remaining high bits default to `'1'` (`x"AAAA"` initialisation). Provide a full 16-bit pattern to avoid surprises.

**Example**

```vhdl
fc.set_mode("PATTERN");
fc.set_pattern("1110");  -- ready 3 out of 4 cycles
```

---

### `ready_this_cycle`

```vhdl
impure function ready_this_cycle return boolean;
```

Returns `true` if the controller allows a transaction this iteration. Advances internal state (random seed or pattern index).

**Example**

```vhdl
-- Inter-transaction gap injection
if not fc_gap.ready_this_cycle then
    wait until rising_edge(clk);
end if;

-- Write vs read decision
if fc_txn.ready_this_cycle then
    -- perform write
else
    -- perform read
end if;
```

---

## Full Example

```vhdl
shared variable fc_gap : t_flow_controller;
shared variable fc_txn : t_flow_controller;

-- Setup
fc_gap.set_mode("RANDOM");
fc_gap.set_throttle(80);   -- 80% no gap, 20% one-cycle gap

fc_txn.set_mode("THROTTLE");
fc_txn.set_throttle(60);   -- 60% write, 40% read

-- Stimulus loop
while not all_covered loop
    -- Optional gap
    if not fc_gap.ready_this_cycle then
        wait until rising_edge(clk);
    end if;

    if fc_txn.ready_this_cycle then
        -- write transaction
    else
        -- read transaction
    end if;
end loop;
```
