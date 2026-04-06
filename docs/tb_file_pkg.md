# tb_file_pkg

File comparison utility for VHDL testbenches. Compares two text files line-by-line and reports mismatches via the standard `print` logging infrastructure.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/tb_file_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

Primarily used to verify DUT output against a golden reference file. Works with any line-oriented text format; designed around the `<hex_tdata> <tuser> <tlast>` format produced by `axis_read_to_file` in `axis_pkg`.

---

## Procedures

### `file_compare`

```vhdl
procedure file_compare(
    constant filename_a : in string;
    constant filename_b : in string
);
```

Reads both files simultaneously, line by line. Reports every mismatch — does not stop on the first difference. Prints a PASS or FAIL summary at the end.

**Behaviour:**

1. If either file cannot be opened, logs `ERROR` and returns immediately.
2. Reads one line from each file per iteration.
3. Paired blank lines (both simultaneously blank) are skipped without incrementing the line counter. A blank line in one file paired with a non-blank line in the other is treated as a mismatch.
4. On mismatch: `[ERROR] [file_compare] line N: a=<val_a> b=<val_b>`
5. If line counts differ: `[ERROR] [file_compare] files have different line counts`
6. Final summary: `[INFO] [file_compare] PASS -- files match (N lines)` or `[ERROR] [file_compare] FAIL -- N mismatches`

**File extension:** Any extension is accepted (`.txt`, `.hex`, `.mem`). File paths are relative to the simulator working directory (when using the Makefile, that is the repo root).

**Example — video loopback test**

```vhdl
-- Drive stimulus from file
axis_write(clk, tvalid, tready, tdata, tlast, tuser, "tb/frame_in.txt");

-- Capture DUT output (1920x1080 frame)
axis_read_to_file(clk, tvalid, tready, tdata, tlast, tuser,
                  "work/frame_out.txt", 1920*1080);

-- Compare
file_compare("tb/frame_in.txt", "work/frame_out.txt");
```

**Limitations**

- Comparison is string-based (no value re-parsing). Both files must use the same hex case (uppercase) and spacing. Files produced by `axis_read_to_file` are always uppercase and will match a stimulus file written in the same format.
- Blank-line skipping is symmetric: if only one file has a blank line at a given position, that is reported as a mismatch, not silently skipped.
