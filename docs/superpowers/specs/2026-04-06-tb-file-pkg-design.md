# Design Spec: Phase 3 — File I/O (`tb_file_pkg` + `axis_pkg` extensions)

**Date:** 2026-04-06
**Status:** Approved

## Goal

Enable stimulus-file-driven video testbenches: load a hex stimulus file, drive it over AXI-Stream to the DUT, capture the DUT output back to a file in the same format, then compare the two files. Matches the UG934-style hex video format used by Xilinx tooling.

---

## File Format

One AXI-Stream beat per line, space-separated fields:

```
<hex_tdata> <tuser> <tlast>
```

- `hex_tdata` — pixel/data value in hexadecimal (no `0x` prefix), width inferred from signal at call site
- `tuser` — `0` or `1`; `1` marks start-of-frame (first beat of a new frame)
- `tlast` — `0` or `1`; `1` marks end-of-line (last beat on a video scan line)

Blank lines and lines that fail to parse are silently skipped.

**File extension:** `.txt` is conventional for this flow. `.hex` and `.mem` are equally valid — the procedures accept any extension. `.mem` is common in Xilinx `$readmemh`-based flows.

### Example (4-pixel, 2-line, 1-frame snippet)

```
FF0000 1 0   ← start-of-frame, mid-line
00FF00 0 0
0000FF 0 0
A1B2C3 0 1   ← end-of-line
```

---

## Changes to `axis_pkg`

Two new procedure overloads. Existing procedures are unchanged.

### `axis_write` — single beat with TUSER

```vhdl
procedure axis_write(
  signal   clk    : in  std_logic;
  signal   tvalid : out std_logic;
  signal   tready : in  std_logic;
  signal   tdata  : out std_logic_vector;
  signal   tlast  : out std_logic;
  signal   tuser  : out std_logic;
  constant data   : in  std_logic_vector;
  constant last   : in  boolean := true;
  constant user   : in  std_logic := '0'
);
```

Drives one beat with `tuser` set from `user`. Mirrors the existing single-beat `axis_write` signature, adding `tuser` and `user` formals. The file-replay overload below calls this internally.

---

### `axis_write` — file-replay with TUSER

```vhdl
procedure axis_write(
  signal   clk      : in  std_logic;
  signal   tvalid   : out std_logic;
  signal   tready   : in  std_logic;
  signal   tdata    : out std_logic_vector;
  signal   tlast    : out std_logic;
  signal   tuser    : out std_logic;
  constant filename : in  string
);
```

Reads the file line-by-line. For each valid line, drives one AXI-Stream beat using the existing single-beat `axis_write` (with `tuser` and `tlast` set from the file fields). Prints each beat at `INFO` level before driving.

### `axis_read_to_file` — capture to file

```vhdl
procedure axis_read_to_file(
  signal   clk       : in  std_logic;
  signal   tvalid    : in  std_logic;
  signal   tready    : out std_logic;
  signal   tdata     : in  std_logic_vector;
  signal   tlast     : in  std_logic;
  signal   tuser     : in  std_logic;
  constant filename  : in  string;
  constant num_beats : in  positive
);
```

Captures exactly `num_beats` AXI-Stream beats. For each beat, asserts `tready`, waits for `tvalid`, then writes one line to the file in the shared format. The caller determines `num_beats` from image dimensions (e.g. `width * height`).

---

## New Package: `tb_file_pkg`

Single procedure. No signal ports — pure file I/O. Depends on `tb_utils_pkg` for `print`.

### `file_compare`

```vhdl
procedure file_compare(
  constant filename_a : in string;
  constant filename_b : in string
);
```

**Behaviour:**

1. Opens both files. If either fails to open, logs `ERROR` and returns.
2. Reads both files line-by-line simultaneously, skipping blank lines in both.
3. For each line pair, compares as strings (no re-parsing needed — same format written by both sides).
4. On mismatch: `print(ERROR, "[file_compare] line <N>: a=<val_a> b=<val_b>")`. Does **not** stop early — all mismatches are reported.
5. If line counts differ after both files are exhausted, logs `ERROR` with the count difference.
6. Final summary: `print(INFO, "[file_compare] PASS — files match")` or `print(ERROR, "[file_compare] FAIL — <N> mismatches")`.

---

## Compilation Order

`tb_file_pkg` inserts after `tb_utils_pkg`:

1. `tb_utils_pkg`
2. **`tb_file_pkg`** ← new
3. `tb_assert_pkg`
4. `tb_scoreboard_pkg`
5. `axis_pkg` (now with two additional overloads)
6. `axi_lite_pkg`
7. `prng_pkg`
8. `coverage_pkg`
9. `sequence_pkg`
10. `flow_ctrl_pkg`

---

## Self-Test Testbench (`tb/file_tb.vhd`)

Loopback pattern:

1. Write a small synthetic frame (e.g. 4×2 pixels) to `test_input.txt` using `axis_write`.
2. Pass through a trivial combinatorial loopback (`tdata` passthrough, `tvalid`/`tready`/`tlast`/`tuser` wired through).
3. Capture output with `axis_read_to_file` to `test_output.txt`.
4. Call `file_compare("test_input.txt", "test_output.txt")` — expect PASS.
5. Call `file_compare` on two deliberately mismatched files — expect logged ERROR(s).

---

## Out of Scope

- `read_hex_file` / `write_hex_file` returning array types (roadmap Phase 3 literal spec) — deferred; the streaming procedures cover the primary use case without requiring a VHDL array type design decision.
- `read_csv` / `write_csv` — deferred to a future increment.
- Multi-frame capture (stopping on TUSER N times) — `num_beats` is sufficient for the initial use case.
