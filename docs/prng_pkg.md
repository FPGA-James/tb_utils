# prng_pkg

Pseudo-random number generator with multiple distributions. Based on the Wichmann-Hill algorithm via `ieee.math_real.uniform` — repeatable with the same seed, suitable for directed-random and constrained-random testbenches.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/prng_pkg.vhd` |
| Depends on | Nothing (uses `ieee.math_real`) |
| VHDL standard | 2008 |

Declare as a shared variable so multiple processes can share the same RNG state:

```vhdl
shared variable rng : rand_t;
```

---

## Methods

### `seed`

```vhdl
procedure seed(s1 : positive; s2 : positive);
```

Initialises the RNG with two seed values. Call once at the start of simulation. Using the same seeds produces identical sequences — useful for reproducible regression runs.

**Example**

```vhdl
rng.seed(42, 7);
```

---

### `get_seed`

```vhdl
procedure get_seed(variable s1 : out positive; variable s2 : out positive);
```

Returns the current internal state. Useful for checkpointing and replaying a specific sub-sequence.

**Example**

```vhdl
variable s1, s2 : positive;
variable v1, v2 : integer;

rng.get_seed(s1, s2);
v1 := rng.rand_int(0, 100);

-- Rewind to the same state
rng.seed(s1, s2);
v2 := rng.rand_int(0, 100);
-- v1 = v2 guaranteed
```

---

### `rand_int`

```vhdl
impure function rand_int(lo : integer; hi : integer) return integer;
```

Returns a uniformly distributed integer in `[lo, hi]` inclusive.

**Limitations**
- `lo` must be ≤ `hi`.
- Range is limited by `integer` range; very large ranges may have slight non-uniformity due to modulo bias.

**Example**

```vhdl
widx := rng.rand_int(0, 3);       -- random register index 0-3
delay := rng.rand_int(1, 20);     -- random delay 1-20 cycles
```

---

### `rand_slv`

```vhdl
impure function rand_slv(width : positive) return std_logic_vector;
```

Returns a random `std_logic_vector` of the given bit width. All bit patterns are equally likely.

**Example**

```vhdl
wr_data := std_logic_vector(to_unsigned(hbyte, 8)) & rng.rand_slv(24);
```

---

### `rand_bool`

```vhdl
impure function rand_bool return boolean;
```

Returns `true` or `false` with equal probability.

**Example**

```vhdl
if rng.rand_bool then
    -- do write
else
    -- do read
end if;
```

---

### `rand_sl`

```vhdl
impure function rand_sl return std_logic;
```

Returns `'0'` or `'1'` with equal probability.

**Example**

```vhdl
tlast <= rng.rand_sl;
```

---

### `rand_time`

```vhdl
impure function rand_time(
    lo         : time;
    hi         : time;
    resolution : time := 1 ns
) return time;
```

Returns a random time value in `[lo, hi]` quantised to `resolution`.

**Example**

```vhdl
wait for rng.rand_time(5 ns, 50 ns, 1 ns);
```

---

### `rand_aligned_addr`

```vhdl
impure function rand_aligned_addr(
    width     : positive;
    alignment : positive
) return std_logic_vector;
```

Returns a random `width`-bit address that is naturally aligned to `alignment` bytes (i.e., the low `log2(alignment)` bits are zero).

**Limitations**
- `alignment` must be a power of 2.

**Example**

```vhdl
-- 32-bit word-aligned address
addr := rng.rand_aligned_addr(32, 4);

-- 64-bit cache-line aligned (64-byte boundary)
addr := rng.rand_aligned_addr(32, 64);
```

---

### `rand_onehot`

```vhdl
impure function rand_onehot(width : positive) return std_logic_vector;
```

Returns a `width`-bit vector with exactly one bit set, chosen uniformly.

**Example**

```vhdl
byte_enable <= rng.rand_onehot(4);  -- exactly one byte lane active
```

---

### `rand_weighted`

```vhdl
impure function rand_weighted(weights : integer_vector) return integer;
```

Returns a 0-based index into `weights`, with each index selected proportional to its weight. Useful for biased stimulus generation.

**Limitations**
- All weights must be ≥ 0; at least one must be > 0.
- Returns 0 if all weights are zero (degenerate case).

**Example**

```vhdl
-- Write 70% of the time, read 30%
txn_kind := rng.rand_weighted((70, 30));
-- 0 => write, 1 => read
```

---

### `rand_gaussian`

```vhdl
impure function rand_gaussian(
    mean   : real;
    stddev : real;
    lo     : integer;
    hi     : integer
) return integer;
```

Returns an integer drawn from a Gaussian (normal) distribution with the given mean and standard deviation, clamped to `[lo, hi]`. Uses the Box-Muller transform internally.

**Limitations**
- Degenerate case `stddev = 0.0` returns `integer(mean)`.
- Heavy tails may be clipped frequently if `[lo, hi]` is narrow relative to `stddev`.

**Example**

```vhdl
-- Most packet sizes cluster around 512 bytes, rarely below 64 or above 1500
pkt_len := rng.rand_gaussian(512.0, 128.0, 64, 1500);
```
