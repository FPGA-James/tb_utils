# sequence_pkg

Deterministic stimulus sequence generator. Produces a predictable stream of integer values useful for directed testing: incrementing sweeps, boundary walks, alternating high/low, and walking-ones/zeros patterns.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/sequence_pkg.vhd` |
| Depends on | Nothing |
| VHDL standard | 2008 |

Declare as a shared variable:

```vhdl
shared variable seq : t_sequence;
```

---

## Modes

| Mode | Description |
|------|-------------|
| `INC` | Increment from `lo` to `hi`, then wrap back to `lo` |
| `DEC` | Decrement from `hi` to `lo`, then wrap back to `hi` |
| `WALK1` | Walking-ones: single `'1'` bit shifts left across `width` bits |
| `WALK0` | Walking-zeros: single `'0'` bit shifts left across `width` bits |
| `ALT` | Alternates between `lo` and `hi` |
| `CONST` | Always returns `current` (set via `set_range`) |

---

## Methods

### `set_mode`

```vhdl
procedure set_mode(m : string);
```

Sets the sequence mode. Valid strings: `"INC"`, `"DEC"`, `"WALK1"`, `"WALK0"`, `"ALT"`, `"CONST"`. Resets `current` to `lo_val` and clears the alternation toggle.

**Example**

```vhdl
seq.set_mode("WALK1");
seq.set_mode("INC");
```

---

### `set_range`

```vhdl
procedure set_range(lo, hi : integer);
```

Sets the lower and upper bounds of the sequence. Also resets `current` to `lo`.

**Limitations**
- `lo` must be ≤ `hi` for `INC`/`ALT` modes to behave correctly.
- For `WALK1`/`WALK0`, `lo` and `hi` are not directly used for the walk itself (the walk depends on `width`), but `set_range` still resets `current`.

**Example**

```vhdl
seq.set_range(0, 255);    -- full byte sweep
seq.set_range(1, 128);    -- for WALK1 high-byte: 1,2,4,8,...,128
```

---

### `set_width`

```vhdl
procedure set_width(w : natural);
```

Sets the bit width used by `WALK1` and `WALK0` modes. The walk wraps after `w` steps.

**Example**

```vhdl
seq.set_width(8);   -- 8-bit walking ones: 1, 2, 4, 8, 16, 32, 64, 128, 1, ...
seq.set_width(32);  -- 32-bit walking ones
```

---

### `next_val`

```vhdl
impure function next_val return integer;
```

Returns the current value and advances the internal state. Each call produces the next value in the sequence.

**Limitations**
- `next_val` is `impure` (modifies state) — do not call it in concurrent signal assignments or functions where pure behaviour is required.

**Example**

```vhdl
for i in 0 to 7 loop
    data_in <= std_logic_vector(to_unsigned(seq.next_val, 8));
    wait until rising_edge(clk);
end loop;
```

---

### `reset`

```vhdl
procedure reset;
```

Resets `current` back to `lo_val` and clears the alternation toggle. Does not change the mode, range, or width.

**Example**

```vhdl
-- Re-run the same directed sweep
seq.reset;
for i in 0 to 255 loop
    data_in <= std_logic_vector(to_unsigned(seq.next_val, 8));
    wait until rising_edge(clk);
end loop;
```

---

## Full Example

```vhdl
shared variable seq : t_sequence;

-- Walking-ones through an 8-bit bus (directed phase)
seq.set_mode("WALK1");
seq.set_width(8);
seq.set_range(1, 128);

for i in 0 to 7 loop
    hbyte   := seq.next_val;         -- 1, 2, 4, 8, 16, 32, 64, 128
    wr_data := std_logic_vector(to_unsigned(hbyte, 8)) & x"000000";
    -- issue write...
end loop;

-- Switch to full incrementing sweep
seq.set_mode("INC");
seq.set_range(0, 255);

for i in 0 to 255 loop
    addr <= std_logic_vector(to_unsigned(seq.next_val, 8));
    wait until rising_edge(clk);
end loop;
```
