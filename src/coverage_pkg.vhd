-- =============================================================================
-- coverage_pkg.vhd
-- Functional coverage package for VHDL testbenches (no OSVVM dependency)
--
-- Features:
--   - Named coverage object (set_name)
--   - Named bins with configurable ranges and hit targets
--   - Illegal bins (fire ERROR on sample; excluded from coverage %)
--   - Weighted bins (per-bin hit targets)
--   - Per-bin hit counts
--   - 2-signal cross-coverage matrix
--   - is_covered query and get_uncovered string for loop conditions
--   - reset (clear hits, keep bin definitions)
--   - Report via tb_pkg print() and/or text file
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;

package coverage_pkg is

  -- Tune these constants for your project
  constant MAX_BINS     : integer := 32;
  constant MAX_NAME_LEN : integer := 32;

  subtype t_bin_name is string(1 to MAX_NAME_LEN);

  -- Single bin descriptor
  type t_bin is record
    name    : t_bin_name;  -- human-readable label
    min     : integer;     -- inclusive range minimum
    max     : integer;     -- inclusive range maximum
    weight  : positive;    -- hits required to be "covered"
    hits    : natural;     -- actual hit count
    illegal : boolean;     -- if true: ERROR on sample, excluded from coverage %
  end record;

  type t_bin_array   is array(0 to MAX_BINS - 1)                     of t_bin;
  type t_cross_array is array(0 to MAX_BINS - 1, 0 to MAX_BINS - 1) of natural;

  -- ---------------------------------------------------------------------------
  -- Protected coverage collector
  -- ---------------------------------------------------------------------------
  type t_coverage is protected

    -- ---- Setup ---------------------------------------------------------------

    -- Name this coverage object; shown in reports when set.
    procedure set_name(name : in string);

    -- Add a 1D coverage bin.
    procedure add_bin(
      name   : in string;
      min    : in integer;
      max    : in integer;
      weight : in positive := 1
    );

    -- Add an illegal bin: any sample that hits it fires an ERROR.
    -- Illegal bins are excluded from the coverage percentage.
    procedure add_illegal_bin(
      name : in string;
      min  : in integer;
      max  : in integer
    );

    -- ---- Sampling ------------------------------------------------------------

    -- Sample a value into 1D bins. Fires ERROR if it hits an illegal bin.
    procedure sample(value : in integer);

    -- Sample a pair of values into the cross-coverage matrix.
    -- Both values are looked up against the SAME bin definitions.
    -- Skipped silently if either value lands in an illegal bin.
    procedure sample_cross(val_a : in integer; val_b : in integer);

    -- ---- Queries -------------------------------------------------------------

    -- Percentage of non-illegal bins that have reached their weight target.
    impure function get_coverage       return real;

    -- Percentage of cross-bin cells (bin_a x bin_b) that have >= 1 hit.
    impure function get_cross_coverage return real;

    -- Total number of defined bins (including illegal bins).
    impure function get_bin_count      return integer;

    -- True when all non-illegal bins have reached their weight target.
    impure function is_covered         return boolean;

    -- Comma-separated names of non-illegal bins that are not yet covered.
    -- Returns "none" when all bins are covered.
    impure function get_uncovered      return string;

    -- Coverage-directed random value.
    -- Selects an uncovered bin weighted by remaining hits needed, then picks
    -- a position within its [min..max] range.
    -- bin_ticket: random integer used for weighted bin selection.
    -- pos_ticket: random integer used for position within the chosen bin.
    -- When all bins are covered, returns a value from the first non-illegal bin.
    impure function rand_cov_point(bin_ticket : integer;
                                   pos_ticket : integer) return integer;

    -- ---- Reset ---------------------------------------------------------------

    -- Clear all hit counts and cross matrix; bin definitions are preserved.
    procedure reset;

    -- ---- Reporting -----------------------------------------------------------

    -- Print a full report via print().
    procedure report_coverage;

    -- Write the same report to a plain-text file.
    procedure write_coverage_file(filename : in string);

    -- Print + write in one call.
    procedure report_all(filename : in string);

  end protected t_coverage;

end package coverage_pkg;


-- =============================================================================
-- Package body
-- =============================================================================
package body coverage_pkg is

  type t_coverage is protected body

    -- ---- Internal state ------------------------------------------------------
    variable v_name      : string(1 to 64)            := (others => ' ');
    variable v_bins      : t_bin_array                := (others => (
      name    => (others => ' '),
      min     => 0,
      max     => 0,
      weight  => 1,
      hits    => 0,
      illegal => false
    ));
    variable v_bin_count : integer range 0 to MAX_BINS := 0;
    variable v_cross     : t_cross_array               := (others => (others => 0));

    -- ---- Private helpers -----------------------------------------------------

    -- Pad/truncate a string into a fixed-length bin name.
    function to_bin_name(s : string) return t_bin_name is
      variable result : t_bin_name := (others => ' ');
      variable j      : integer    := 1;
    begin
      for i in s'range loop
        exit when j > MAX_NAME_LEN;
        result(j) := s(i);
        j         := j + 1;
      end loop;
      return result;
    end function;

    -- Return index of first bin containing 'value', or -1.
    impure function find_bin(value : integer) return integer is
    begin
      for i in 0 to v_bin_count - 1 loop
        if value >= v_bins(i).min and value <= v_bins(i).max then
          return i;
        end if;
      end loop;
      return -1;
    end function;

    -- Format a real as a percentage string.
    function fmt_pct(pct : real) return string is
    begin
      return real'image(pct) & " %";
    end function;

    -- Return a bin name trimmed of trailing spaces.
    function trim_name(s : t_bin_name) return string is
      variable len : integer := MAX_NAME_LEN;
    begin
      while len > 0 and s(len) = ' ' loop
        len := len - 1;
      end loop;
      if len = 0 then return ""; end if;
      return s(1 to len);
    end function;

    -- Return length of v_name after trimming trailing spaces (0 = unset).
    impure function cov_name_len return integer is
      variable len : integer := 64;
    begin
      while len > 0 and v_name(len) = ' ' loop
        len := len - 1;
      end loop;
      return len;
    end function;

    -- ---- Public implementation -----------------------------------------------

    procedure set_name(name : in string) is
    begin
      v_name := (others => ' ');
      for i in name'range loop
        exit when i - name'low + 1 > 64;
        v_name(i - name'low + 1) := name(i);
      end loop;
    end procedure;

    -- --------------------------------------------------------------------------
    procedure add_bin(
      name   : in string;
      min    : in integer;
      max    : in integer;
      weight : in positive := 1
    ) is
    begin
      if v_bin_count >= MAX_BINS then
        print(FATAL, "[coverage.add_bin] MAX_BINS (" & integer'image(MAX_BINS) &
                     ") exceeded - increase the constant.");
      end if;
      v_bins(v_bin_count) := (
        name    => to_bin_name(name),
        min     => min,
        max     => max,
        weight  => weight,
        hits    => 0,
        illegal => false
      );
      v_bin_count := v_bin_count + 1;
    end procedure;

    -- --------------------------------------------------------------------------
    procedure add_illegal_bin(
      name : in string;
      min  : in integer;
      max  : in integer
    ) is
    begin
      if v_bin_count >= MAX_BINS then
        print(FATAL, "[coverage.add_illegal_bin] MAX_BINS (" & integer'image(MAX_BINS) &
                     ") exceeded - increase the constant.");
      end if;
      v_bins(v_bin_count) := (
        name    => to_bin_name(name),
        min     => min,
        max     => max,
        weight  => 1,
        hits    => 0,
        illegal => true
      );
      v_bin_count := v_bin_count + 1;
    end procedure;

    -- --------------------------------------------------------------------------
    procedure sample(value : in integer) is
      variable idx : integer;
    begin
      idx := find_bin(value);
      if idx >= 0 then
        v_bins(idx).hits := v_bins(idx).hits + 1;
        if v_bins(idx).illegal then
          print(ERROR, "[coverage.sample] illegal bin hit: '" &
                       trim_name(v_bins(idx).name) &
                       "' value=" & integer'image(value));
        end if;
      end if;
    end procedure;

    -- --------------------------------------------------------------------------
    procedure sample_cross(val_a : in integer; val_b : in integer) is
      variable idx_a, idx_b : integer;
    begin
      idx_a := find_bin(val_a);
      idx_b := find_bin(val_b);
      if idx_a >= 0 and idx_b >= 0 then
        if not v_bins(idx_a).illegal and not v_bins(idx_b).illegal then
          v_cross(idx_a, idx_b) := v_cross(idx_a, idx_b) + 1;
        end if;
      end if;
    end procedure;

    -- --------------------------------------------------------------------------
    impure function get_coverage return real is
      variable covered : integer := 0;
      variable total   : integer := 0;
    begin
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal then
          total := total + 1;
          if v_bins(i).hits >= v_bins(i).weight then
            covered := covered + 1;
          end if;
        end if;
      end loop;
      if total = 0 then return 0.0; end if;
      return real(covered) / real(total) * 100.0;
    end function;

    -- --------------------------------------------------------------------------
    impure function get_cross_coverage return real is
      variable covered : integer := 0;
      variable total   : integer := 0;
    begin
      -- Count only non-illegal bin pairs
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal then
          for j in 0 to v_bin_count - 1 loop
            if not v_bins(j).illegal then
              total := total + 1;
              if v_cross(i, j) > 0 then
                covered := covered + 1;
              end if;
            end if;
          end loop;
        end if;
      end loop;
      if total = 0 then return 0.0; end if;
      return real(covered) / real(total) * 100.0;
    end function;

    -- --------------------------------------------------------------------------
    impure function get_bin_count return integer is
    begin
      return v_bin_count;
    end function;

    -- --------------------------------------------------------------------------
    impure function is_covered return boolean is
    begin
      return get_coverage = 100.0;
    end function;

    -- --------------------------------------------------------------------------
    impure function get_uncovered return string is
      variable buf  : string(1 to MAX_BINS * (MAX_NAME_LEN + 2));
      variable pos  : integer := 1;
      variable n    : t_bin_name;
      variable nlen : integer;
    begin
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal and v_bins(i).hits < v_bins(i).weight then
          if pos > 1 then
            buf(pos) := ','; buf(pos + 1) := ' '; pos := pos + 2;
          end if;
          n    := v_bins(i).name;
          nlen := MAX_NAME_LEN;
          while nlen > 0 and n(nlen) = ' ' loop nlen := nlen - 1; end loop;
          if nlen > 0 then
            buf(pos to pos + nlen - 1) := n(1 to nlen);
            pos := pos + nlen;
          end if;
        end if;
      end loop;
      if pos = 1 then return "none"; end if;
      return buf(1 to pos - 1);
    end function;

    -- --------------------------------------------------------------------------
    impure function rand_cov_point(bin_ticket : integer;
                                   pos_ticket : integer) return integer is
      variable total_w   : integer := 0;
      variable pick      : integer;
      variable running   : integer := 0;
      variable sel       : integer := 0;
      variable range_sz  : integer;
    begin
      -- Sum remaining hits needed across all uncovered non-illegal bins
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal and v_bins(i).hits < v_bins(i).weight then
          total_w := total_w + (v_bins(i).weight - v_bins(i).hits);
        end if;
      end loop;

      if total_w = 0 then
        -- All covered: return a value from the first non-illegal bin
        for i in 0 to v_bin_count - 1 loop
          if not v_bins(i).illegal then
            range_sz := v_bins(i).max - v_bins(i).min + 1;
            return v_bins(i).min + (pos_ticket mod range_sz);
          end if;
        end loop;
        return 0;
      end if;

      -- Weighted bin selection: bins with more remaining hits get higher weight
      pick := bin_ticket mod total_w;
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal and v_bins(i).hits < v_bins(i).weight then
          running := running + (v_bins(i).weight - v_bins(i).hits);
          if pick < running then
            sel := i;
            exit;
          end if;
        end if;
      end loop;

      -- Pick position within the selected bin's range
      range_sz := v_bins(sel).max - v_bins(sel).min + 1;
      return v_bins(sel).min + (pos_ticket mod range_sz);
    end function;

    -- --------------------------------------------------------------------------
    procedure reset is
    begin
      for i in 0 to v_bin_count - 1 loop
        v_bins(i).hits := 0;
      end loop;
      v_cross := (others => (others => 0));
    end procedure;

    -- ---- Report helpers ------------------------------------------------------

    procedure write_report_to_file(file f : text) is
      variable l        : line;
      variable nlen     : integer;
      variable has_ill  : boolean := false;
    begin
      -- Header
      write(l, string'("================================================================="));
      writeline(f, l);
      nlen := cov_name_len;
      if nlen > 0 then
        write(l, string'("  Functional Coverage Report: ") & v_name(1 to nlen));
      else
        write(l, string'("  Functional Coverage Report"));
      end if;
      writeline(f, l);
      write(l, string'("================================================================="));
      writeline(f, l);

      -- 1D bins (non-illegal)
      write(l, string'("  1D Bins"));
      writeline(f, l);
      write(l, string'("  -------"));
      writeline(f, l);
      write(l, string'("  Idx  Name                              Range            Hits   Target  OK?"));
      writeline(f, l);
      write(l, string'("  ---  --------------------------------  ---------------  -----  ------  ---"));
      writeline(f, l);

      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal then
          write(l, string'("  "));
          write(l, i,                right, 3);
          write(l, string'("  "));
          write(l, v_bins(i).name);
          write(l, string'("  ["));
          write(l, v_bins(i).min,    right, 6);
          write(l, string'(".."));
          write(l, v_bins(i).max,    right, 6);
          write(l, string'("]  "));
          write(l, v_bins(i).hits,   right, 5);
          write(l, string'("  "));
          write(l, v_bins(i).weight, right, 6);
          write(l, string'("  "));
          if v_bins(i).hits >= v_bins(i).weight then
            write(l, string'("YES"));
          else
            write(l, string'(" NO"));
          end if;
          writeline(f, l);
        else
          has_ill := true;
        end if;
      end loop;

      writeline(f, l);
      write(l, string'("  1D Coverage : ") & fmt_pct(get_coverage));
      writeline(f, l);
      writeline(f, l);

      -- Cross-coverage matrix (non-illegal bins only)
      write(l, string'("  Cross-Coverage Matrix  (rows = val_a bin, cols = val_b bin)"));
      writeline(f, l);
      write(l, string'("     "));
      for j in 0 to v_bin_count - 1 loop
        if not v_bins(j).illegal then
          write(l, j, right, 6);
        end if;
      end loop;
      writeline(f, l);
      write(l, string'("  ---"));
      for j in 0 to v_bin_count - 1 loop
        if not v_bins(j).illegal then
          write(l, string'("  ----"));
        end if;
      end loop;
      writeline(f, l);
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal then
          write(l, string'("  "));
          write(l, i, right, 3);
          write(l, string'("  "));
          for j in 0 to v_bin_count - 1 loop
            if not v_bins(j).illegal then
              write(l, v_cross(i, j), right, 6);
            end if;
          end loop;
          writeline(f, l);
        end if;
      end loop;
      writeline(f, l);
      write(l, string'("  Cross Coverage : ") & fmt_pct(get_cross_coverage));
      writeline(f, l);

      -- Illegal bins section (if any)
      if has_ill then
        writeline(f, l);
        write(l, string'("  Illegal Bins (0 hits expected)"));
        writeline(f, l);
        write(l, string'("  -------"));
        writeline(f, l);
        for i in 0 to v_bin_count - 1 loop
          if v_bins(i).illegal then
            write(l, string'("  "));
            write(l, i, right, 3);
            write(l, string'("  "));
            write(l, v_bins(i).name);
            write(l, string'("  ["));
            write(l, v_bins(i).min, right, 6);
            write(l, string'(".."));
            write(l, v_bins(i).max, right, 6);
            write(l, string'("]  hits="));
            write(l, v_bins(i).hits, right, 5);
            if v_bins(i).hits > 0 then
              write(l, string'("  *** VIOLATED ***"));
            end if;
            writeline(f, l);
          end if;
        end loop;
      end if;

      write(l, string'("================================================================="));
      writeline(f, l);
    end procedure;

    -- --------------------------------------------------------------------------
    procedure report_coverage is
      variable nlen    : integer;
      variable has_ill : boolean := false;
    begin
      print(INFO, "[coverage.report] =================================================================");
      nlen := cov_name_len;
      if nlen > 0 then
        print(INFO, "[coverage.report]   Functional Coverage Report: " & v_name(1 to nlen));
      else
        print(INFO, "[coverage.report]   Functional Coverage Report");
      end if;
      print(INFO, "[coverage.report] =================================================================");

      -- 1D bins (non-illegal)
      print(INFO, "[coverage.report]   1D Bins:");
      for i in 0 to v_bin_count - 1 loop
        if not v_bins(i).illegal then
          print(INFO, "[coverage.report]   [" & integer'image(i) & "] " &
                      trim_name(v_bins(i).name) &
                      "  range=[" & integer'image(v_bins(i).min) &
                      ".."        & integer'image(v_bins(i).max) & "]" &
                      "  hits="   & integer'image(v_bins(i).hits) &
                      "  target=" & integer'image(v_bins(i).weight) &
                      "  covered=" & boolean'image(v_bins(i).hits >= v_bins(i).weight));
        else
          has_ill := true;
        end if;
      end loop;
      print(INFO, "[coverage.report]   1D Coverage   : " & fmt_pct(get_coverage));
      print(INFO, "[coverage.report]   Cross Coverage: " & fmt_pct(get_cross_coverage));

      -- Cross matrix (non-zero cells)
      print(INFO, "[coverage.report]   Cross Matrix (non-zero cells):");
      for i in 0 to v_bin_count - 1 loop
        for j in 0 to v_bin_count - 1 loop
          if v_cross(i, j) > 0 and not v_bins(i).illegal and not v_bins(j).illegal then
            print(INFO, "[coverage.report]     [" & integer'image(i) & "][" &
                        integer'image(j) & "] = " & integer'image(v_cross(i, j)));
          end if;
        end loop;
      end loop;

      -- Illegal bins
      if has_ill then
        print(INFO, "[coverage.report]   Illegal Bins (0 hits expected):");
        for i in 0 to v_bin_count - 1 loop
          if v_bins(i).illegal then
            if v_bins(i).hits > 0 then
              print(ERROR, "[coverage.report]   [" & integer'image(i) & "] " &
                           trim_name(v_bins(i).name) &
                           "  range=[" & integer'image(v_bins(i).min) &
                           ".."        & integer'image(v_bins(i).max) & "]" &
                           "  hits=" & integer'image(v_bins(i).hits) &
                           "  *** VIOLATED ***");
            else
              print(INFO, "[coverage.report]   [" & integer'image(i) & "] " &
                          trim_name(v_bins(i).name) &
                          "  range=[" & integer'image(v_bins(i).min) &
                          ".."        & integer'image(v_bins(i).max) & "]" &
                          "  hits=0  OK");
            end if;
          end if;
        end loop;
      end if;

      print(INFO, "[coverage.report] =================================================================");
    end procedure;

    -- --------------------------------------------------------------------------
    procedure write_coverage_file(filename : in string) is
      file     f      : text;
      variable status : file_open_status;
    begin
      file_open(status, f, filename, write_mode);
      if status /= open_ok then
        print(FATAL, "[coverage.write] cannot open file '" & filename & "'");
      end if;
      write_report_to_file(f);
      file_close(f);
      print(INFO, "[coverage.write] report written to '" & filename & "'");
    end procedure;

    -- --------------------------------------------------------------------------
    procedure report_all(filename : in string) is
    begin
      report_coverage;
      write_coverage_file(filename);
    end procedure;

  end protected body t_coverage;

end package body coverage_pkg;
