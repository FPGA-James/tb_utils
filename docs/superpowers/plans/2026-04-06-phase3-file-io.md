# Phase 3 File I/O Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `tb_file_pkg` (file comparison) and TUSER-aware AXI-Stream file-replay/capture to `axis_pkg`, enabling stimulus-file-driven video testbenches.

**Architecture:** Extend `axis_pkg` with three new overloads (single-beat with TUSER, file-replay with TUSER, capture-to-file); add a new `tb_file_pkg` package with `file_compare`. All file I/O uses VHDL `std.textio` — no external dependencies. File format is `<hex_tdata> <tuser> <tlast>` per line.

**Tech Stack:** VHDL-2008, GHDL, `std.textio`, GNU Make

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/tb_file_pkg.vhd` | `file_compare` procedure |
| Modify | `src/axis_pkg.vhd` | Add 3 TUSER overloads |
| Modify | `Makefile` | Register new source + testbench |
| Create | `tb/file_tb.vhd` | Self-test testbench |
| Create | `tb/test_input.txt` | 8-beat 24-bit RGB stimulus fixture |
| Create | `tb/test_mismatch.txt` | Deliberately broken fixture for FAIL path |

---

## Task 1: Create stimulus fixture files

**Files:**
- Create: `tb/test_input.txt`
- Create: `tb/test_mismatch.txt`

- [ ] **Step 1: Create `tb/test_input.txt`**

  8 beats representing a 4×2 pixel frame. 24-bit RGB. `tuser=1` on the first beat (start-of-frame). `tlast=1` on the last beat of each line.

  ```
  FF0000 1 0
  00FF00 0 0
  0000FF 0 0
  A1B2C3 0 1
  112233 0 0
  445566 0 0
  778899 0 0
  AABBCC 0 1
  ```

- [ ] **Step 2: Create `tb/test_mismatch.txt`**

  Identical to `test_input.txt` except line 6 (`445566`) is changed to `FFFFFF`. Used to exercise the FAIL path of `file_compare`.

  ```
  FF0000 1 0
  00FF00 0 0
  0000FF 0 0
  A1B2C3 0 1
  112233 0 0
  FFFFFF 0 0
  778899 0 0
  AABBCC 0 1
  ```

---

## Task 2: Create `tb_file_pkg` skeleton and update Makefile SRC

**Files:**
- Create: `src/tb_file_pkg.vhd`
- Modify: `Makefile`

- [ ] **Step 1: Create `src/tb_file_pkg.vhd` with stub body**

  ```vhdl
  library ieee;
  use ieee.std_logic_1164.all;
  use std.textio.all;
  library tb_utils;
  use tb_utils.tb_utils_pkg.all;

  package tb_file_pkg is

    -- Compare two text files line-by-line.
    -- Reports all mismatches via print(ERROR,...). Prints PASS/FAIL summary at end.
    procedure file_compare(
      constant filename_a : in string;
      constant filename_b : in string
    );

  end package tb_file_pkg;

  package body tb_file_pkg is

    procedure file_compare(
      constant filename_a : in string;
      constant filename_b : in string
    ) is
    begin
      print(INFO, "[file_compare] stub — not yet implemented");
    end procedure;

  end package body tb_file_pkg;
  ```

- [ ] **Step 2: Add `tb_file_pkg.vhd` to Makefile SRC (after `tb_utils_pkg.vhd`)**

  Change the `SRC` block from:
  ```makefile
  SRC := \
    src/tb_utils_pkg.vhd \
    src/tb_assert_pkg.vhd \
  ```
  To:
  ```makefile
  SRC := \
    src/tb_utils_pkg.vhd \
    src/tb_file_pkg.vhd \
    src/tb_assert_pkg.vhd \
  ```

---

## Task 3: Write `file_tb.vhd` testbench and update Makefile — compile will fail

**Files:**
- Create: `tb/file_tb.vhd`
- Modify: `Makefile`

The testbench calls procedures that don't exist yet in `axis_pkg`. The compile failure is expected and confirms the tests are genuinely exercising the new API.

- [ ] **Step 1: Create `tb/file_tb.vhd`**

  ```vhdl
  library ieee;
  use ieee.std_logic_1164.all;
  library tb_utils;
  use tb_utils.tb_utils_pkg.all;
  use tb_utils.tb_file_pkg.all;
  use tb_utils.axis_pkg.all;

  entity file_tb is
  end entity file_tb;

  architecture sim of file_tb is
    signal clk    : std_logic := '0';
    signal tvalid : std_logic := '0';
    signal tready : std_logic := '0';
    signal tdata  : std_logic_vector(23 downto 0) := (others => '0');
    signal tlast  : std_logic := '0';
    signal tuser  : std_logic := '0';
  begin

    clk_proc : process
    begin
      clk_gen(clk, 10 ns);
    end process;

    -- Slave: capture 8 beats to file, compare, stop simulation
    slave : process
    begin
      axis_read_to_file(clk, tvalid, tready, tdata, tlast, tuser,
                        "work/test_output.txt", 8);
      -- PASS path: loopback so output matches input
      file_compare("tb/test_input.txt", "work/test_output.txt");
      -- FAIL path: mismatch file has line 6 changed
      file_compare("tb/test_input.txt", "tb/test_mismatch.txt");
      print(INFO, "file_tb: done");
      std.env.stop;
    end process;

    -- Master: drive the 8-beat frame from file, then suspend
    master : process
    begin
      wait for 20 ns;
      axis_write(clk, tvalid, tready, tdata, tlast, tuser, "tb/test_input.txt");
      wait;
    end process;

  end architecture sim;
  ```

- [ ] **Step 2: Add `file_tb` to Makefile**

  Add `tb/file_tb.vhd` to the TBS list:
  ```makefile
  TBS := \
    tb/tb_core_tb.vhd \
    tb/axis_tb.vhd \
    tb/axi_lite_tb.vhd \
    tb/coverage_tb.vhd \
    tb/random_tb.vhd \
    tb/crv_axi_lite_tb.vhd \
    tb/file_tb.vhd
  ```

  Add `file_tb` to TB_TOPS:
  ```makefile
  TB_TOPS := tb_core_tb axis_tb axi_lite_tb coverage_tb random_tb crv_axi_lite_tb file_tb
  ```

- [ ] **Step 3: Confirm compile fails on the new procedures**

  Run:
  ```bash
  make compile 2>&1 | grep -E "error|Error"
  ```

  Expected: errors about `axis_write` and `axis_read_to_file` not matching any declaration (the TUSER overloads don't exist yet). This confirms the testbench is wired to the right new API.

---

## Task 4: Add TUSER procedure declarations to `axis_pkg` header

**Files:**
- Modify: `src/axis_pkg.vhd` (package declaration section only)

- [ ] **Step 1: Add three procedure declarations to `axis_pkg` after the existing `axis_write(filename)` declaration**

  In `src/axis_pkg.vhd`, after the comment/declaration for the existing file-replay `axis_write` (line ~42), add:

  ```vhdl
  -- Master: drive one beat with tuser. Mirrors axis_write but adds tuser/user formals.
  procedure axis_write(
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    signal   tuser  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean   := true;
    constant user   : in  std_logic := '0'
  );

  -- Replay beats from a file with tuser. Each line: "<hex_tdata> <tuser> <tlast>"
  -- Blank and malformed lines are skipped. Prints each beat before driving it.
  procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant filename : in  string
  );

  -- Capture num_beats beats to a file. Each captured line: "<hex_tdata> <tuser> <tlast>"
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

---

## Task 5: Implement the three TUSER procedure bodies in `axis_pkg`

**Files:**
- Modify: `src/axis_pkg.vhd` (package body section)

- [ ] **Step 1: Add `axis_write` single-beat with TUSER body**

  In the package body of `src/axis_pkg.vhd`, after the existing `axis_write` single-beat body (after line ~77), add:

  ```vhdl
  procedure axis_write(
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    signal   tuser  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean   := true;
    constant user   : in  std_logic := '0'
  ) is
  begin
    tdata  <= data;
    tlast  <= '1' when last else '0';
    tuser  <= user;
    tvalid <= '1';
    wait until rising_edge(clk) and tready = '1';
    tvalid <= '0';
    tdata  <= (tdata'range => '0');
    tlast  <= '0';
    tuser  <= '0';
  end procedure;
  ```

- [ ] **Step 2: Add `axis_write` file-replay with TUSER body**

  Immediately after the body added in Step 1, add:

  ```vhdl
  procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant filename : in  string
  ) is
    file     f        : text;
    variable l        : line;
    variable v        : std_logic_vector(tdata'length-1 downto 0);
    variable user_int : integer;
    variable last_int : integer;
    variable user_sl  : std_logic;
    variable good     : boolean;
    variable fstatus  : file_open_status;
  begin
    file_open(fstatus, f, filename, read_mode);
    if fstatus /= open_ok then
      print(FATAL, "[axis.axis_write] cannot open file: " & filename);
      return;
    end if;
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0;
      hread(l, v, good);
      next when not good;
      read(l, user_int, good);
      next when not good;
      read(l, last_int, good);
      next when not good;
      if user_int /= 0 then user_sl := '1'; else user_sl := '0'; end if;
      print(INFO, "[axis.axis_write] data=" & to_hstring(v) &
                  " tuser=" & integer'image(user_int) &
                  " last=" & integer'image(last_int));
      axis_write(clk, tvalid, tready, tdata, tlast, tuser,
                 v, last_int = 1, user_sl);
    end loop;
    file_close(f);
  end procedure;
  ```

- [ ] **Step 3: Add `axis_read_to_file` body**

  Immediately after the body added in Step 2, add:

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
  ) is
    file     f       : text;
    variable l       : line;
    variable fstatus : file_open_status;
  begin
    file_open(fstatus, f, filename, write_mode);
    if fstatus /= open_ok then
      print(FATAL, "[axis.axis_read_to_file] cannot open file: " & filename);
      return;
    end if;
    for i in 1 to num_beats loop
      tready <= '1';
      wait until rising_edge(clk) and tvalid = '1';
      tready <= '0';
      hwrite(l, std_logic_vector(tdata));
      write(l, ' ');
      if tuser = '1' then write(l, 1); else write(l, 0); end if;
      write(l, ' ');
      if tlast = '1' then write(l, 1); else write(l, 0); end if;
      writeline(f, l);
    end loop;
    file_close(f);
    print(INFO, "[axis.axis_read_to_file] captured " &
                integer'image(num_beats) & " beats to " & filename);
  end procedure;
  ```

- [ ] **Step 4: Compile and confirm it succeeds**

  ```bash
  make compile
  ```

  Expected: no errors. The `work/.compiled` file is updated.

---

## Task 6: Implement `file_compare` body in `tb_file_pkg`

**Files:**
- Modify: `src/tb_file_pkg.vhd` (replace stub body)

- [ ] **Step 1: Replace the stub `file_compare` body with the full implementation**

  Replace the entire `package body tb_file_pkg is ... end package body tb_file_pkg;` block with:

  ```vhdl
  package body tb_file_pkg is

    procedure file_compare(
      constant filename_a : in string;
      constant filename_b : in string
    ) is
      file     fa         : text;
      file     fb         : text;
      variable la         : line;
      variable lb         : line;
      variable fsa        : file_open_status;
      variable fsb        : file_open_status;
      variable mismatches : integer := 0;
      variable line_num   : integer := 0;
    begin
      file_open(fsa, fa, filename_a, read_mode);
      if fsa /= open_ok then
        print(ERROR, "[file_compare] cannot open: " & filename_a);
        return;
      end if;
      file_open(fsb, fb, filename_b, read_mode);
      if fsb /= open_ok then
        print(ERROR, "[file_compare] cannot open: " & filename_b);
        file_close(fa);
        return;
      end if;

      while not endfile(fa) and not endfile(fb) loop
        readline(fa, la);
        readline(fb, lb);
        next when la'length = 0 and lb'length = 0;  -- skip paired blank lines
        line_num := line_num + 1;
        if la.all /= lb.all then
          mismatches := mismatches + 1;
          print(ERROR, "[file_compare] line " & integer'image(line_num) &
                       ": a=" & la.all & " b=" & lb.all);
        end if;
      end loop;

      if not endfile(fa) or not endfile(fb) then
        mismatches := mismatches + 1;
        print(ERROR, "[file_compare] files have different line counts");
      end if;

      file_close(fa);
      file_close(fb);

      if mismatches = 0 then
        print(INFO,  "[file_compare] PASS -- files match (" &
                     integer'image(line_num) & " lines)");
      else
        print(ERROR, "[file_compare] FAIL -- " &
                     integer'image(mismatches) & " mismatches");
      end if;
    end procedure;

  end package body tb_file_pkg;
  ```

- [ ] **Step 2: Recompile**

  ```bash
  make compile
  ```

  Expected: clean build, no errors.

---

## Task 7: Run `file_tb` and verify output

**Files:** none changed

- [ ] **Step 1: Run the testbench**

  ```bash
  make run TB=file_tb
  ```

- [ ] **Step 2: Check output contains expected lines**

  Look for these lines in the output (timestamps will vary):

  ```
  [axis.axis_write] data=FF0000 tuser=1 last=0
  [axis.axis_write] data=00FF00 tuser=0 last=0
  ...
  [axis.axis_read_to_file] captured 8 beats to work/test_output.txt
  [file_compare] PASS -- files match (8 lines)
  [file_compare] line 6: a=445566 0 0 b=FFFFFF 0 0
  [file_compare] FAIL -- 1 mismatches
  file_tb: done
  ```

  The PASS line confirms the loopback round-trip is correct. The FAIL line (with line 6 mismatch) confirms the error path works.

- [ ] **Step 3: Verify the captured output file looks right**

  ```bash
  cat work/test_output.txt
  ```

  Expected (uppercase hex, exactly 8 lines):
  ```
  FF0000 1 0
  00FF00 0 0
  0000FF 0 0
  A1B2C3 0 1
  112233 0 0
  445566 0 0
  778899 0 0
  AABBCC 0 1
  ```

---

## Task 8: Run full test suite and commit

**Files:** none changed

- [ ] **Step 1: Run all testbenches**

  ```bash
  make test
  ```

  Expected: all testbenches pass, ending with:
  ```
  === All tests passed ===
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add src/tb_file_pkg.vhd src/axis_pkg.vhd tb/file_tb.vhd \
          tb/test_input.txt tb/test_mismatch.txt Makefile
  git commit -m "feat: add tb_file_pkg (file_compare) and axis_pkg TUSER file-replay/capture

  Phase 3 of tb_utils roadmap. Adds:
  - tb_file_pkg: file_compare procedure for line-by-line file diffing
  - axis_pkg: axis_write single-beat and file-replay with tuser
  - axis_pkg: axis_read_to_file for capturing AXI-Stream to file
  - file_tb: self-test testbench exercising PASS and FAIL paths
  File format: <hex_tdata> <tuser> <tlast> per line (.txt/.hex/.mem all valid)

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

## Spec Coverage Check

| Spec requirement | Task |
|-----------------|------|
| `axis_write` single-beat with TUSER | Task 4+5 |
| `axis_write` file-replay with TUSER, 3-field format | Task 4+5 |
| `axis_read_to_file` capturing N beats | Task 4+5 |
| `tb_file_pkg` with `file_compare` | Task 2+6 |
| `file_compare` open-fail error path | Task 6 |
| `file_compare` line mismatch with line number | Task 6+7 |
| `file_compare` line count mismatch | Task 6 |
| `file_compare` PASS/FAIL summary | Task 6+7 |
| Self-test testbench: PASS path (loopback) | Task 3+7 |
| Self-test testbench: FAIL path (deliberate mismatch) | Task 3+7 |
| Makefile updated | Task 2+3 |
