-- =============================================================================
-- coverage_pkg.vhd
-- Functional coverage package for VHDL testbenches (no OSVVM dependency)
--
-- Features:
--   - Named bins with configurable ranges
--   - Weighted bins (per-bin hit targets)
--   - Per-bin hit counts
--   - 2-signal cross-coverage matrix
--   - Report via 'report' statements and/or text file
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

package coverage_pkg is

    -- Tune these constants for your project
    constant MAX_BINS     : integer := 32;
    constant MAX_NAME_LEN : integer := 32;

    subtype t_bin_name is string(1 to MAX_NAME_LEN);

    -- Single bin descriptor
    type t_bin is record
        name   : t_bin_name;   -- human-readable label
        min    : integer;       -- inclusive range minimum
        max    : integer;       -- inclusive range maximum
        weight : positive;      -- number of hits required to be "covered"
        hits   : natural;       -- actual hit count
    end record;

    type t_bin_array   is array(0 to MAX_BINS - 1)                       of t_bin;
    type t_cross_array is array(0 to MAX_BINS - 1, 0 to MAX_BINS - 1)   of natural;

    -- ---------------------------------------------------------------------------
    -- Protected coverage collector
    -- ---------------------------------------------------------------------------
    type t_coverage is protected

        -- ---- Bin setup --------------------------------------------------------

        -- Add a 1D bin.
        --   weight: how many hits are needed before this bin counts as covered.
        --           Default 1 = hit-once semantics.
        procedure add_bin(
            name   : in string;
            min    : in integer;
            max    : in integer;
            weight : in positive := 1
        );

        -- ---- Sampling ---------------------------------------------------------

        -- Sample a single value into the 1D bins.
        procedure sample(value : in integer);

        -- Sample a pair of values into the cross-coverage matrix.
        -- Both values are looked up against the SAME bin definitions.
        procedure sample_cross(val_a : in integer; val_b : in integer);

        -- ---- Queries ----------------------------------------------------------

        -- Percentage of 1D bins that have reached their weight target.
        impure function get_coverage       return real;

        -- Percentage of cross-bin cells (bin_a x bin_b) that have ≥ 1 hit.
        impure function get_cross_coverage return real;

        -- Number of defined bins.
        impure function get_bin_count      return integer;

        -- ---- Reporting --------------------------------------------------------

        -- Print a full report via VHDL 'report' statements.
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

        -- ---- Internal state --------------------------------------------------
        variable v_bins      : t_bin_array                        := (others => (
            name   => (others => ' '),
            min    => 0,
            max    => 0,
            weight => 1,
            hits   => 0
        ));
        variable v_bin_count : integer range 0 to MAX_BINS        := 0;
        variable v_cross     : t_cross_array                      := (others => (others => 0));

        -- ---- Private helpers -------------------------------------------------

        -- Left-pad a string into a fixed-length bin name.
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

        -- Return the index of the first bin that contains 'value', or -1.
        impure function find_bin(value : integer) return integer is
        begin
            for i in 0 to v_bin_count - 1 loop
                if value >= v_bins(i).min and value <= v_bins(i).max then
                    return i;
                end if;
            end loop;
            return -1;
        end function;

        -- Format a coverage percentage as a trimmed string ("  75.00 %").
        function fmt_pct(pct : real) return string is
        begin
            -- real'image gives enough precision; trim leading space in simulator output
            return real'image(pct) & " %";
        end function;

        -- ---- Public procedures -----------------------------------------------

        procedure add_bin(
            name   : in string;
            min    : in integer;
            max    : in integer;
            weight : in positive := 1
        ) is
        begin
            assert v_bin_count < MAX_BINS
                report "coverage_pkg: MAX_BINS (" & integer'image(MAX_BINS) &
                       ") exceeded - increase the constant."
                severity failure;

            v_bins(v_bin_count) := (
                name   => to_bin_name(name),
                min    => min,
                max    => max,
                weight => weight,
                hits   => 0
            );
            v_bin_count := v_bin_count + 1;
        end procedure;

        -- ----------------------------------------------------------------------
        procedure sample(value : in integer) is
            variable idx : integer;
        begin
            idx := find_bin(value);
            if idx >= 0 then
                v_bins(idx).hits := v_bins(idx).hits + 1;
            end if;
        end procedure;

        -- ----------------------------------------------------------------------
        procedure sample_cross(val_a : in integer; val_b : in integer) is
            variable idx_a, idx_b : integer;
        begin
            idx_a := find_bin(val_a);
            idx_b := find_bin(val_b);
            if idx_a >= 0 and idx_b >= 0 then
                v_cross(idx_a, idx_b) := v_cross(idx_a, idx_b) + 1;
            end if;
        end procedure;

        -- ----------------------------------------------------------------------
        impure function get_coverage return real is
            variable covered : integer := 0;
        begin
            if v_bin_count = 0 then return 0.0; end if;
            for i in 0 to v_bin_count - 1 loop
                if v_bins(i).hits >= v_bins(i).weight then
                    covered := covered + 1;
                end if;
            end loop;
            return real(covered) / real(v_bin_count) * 100.0;
        end function;

        -- ----------------------------------------------------------------------
        impure function get_cross_coverage return real is
            variable covered : integer := 0;
            variable total   : integer := v_bin_count * v_bin_count;
        begin
            if total = 0 then return 0.0; end if;
            for i in 0 to v_bin_count - 1 loop
                for j in 0 to v_bin_count - 1 loop
                    if v_cross(i, j) > 0 then
                        covered := covered + 1;
                    end if;
                end loop;
            end loop;
            return real(covered) / real(total) * 100.0;
        end function;

        -- ----------------------------------------------------------------------
        impure function get_bin_count return integer is
        begin
            return v_bin_count;
        end function;

        -- ---- Report helpers (shared logic) -----------------------------------

        -- Write all report lines into an open 'text' file handle.
        -- Passing an open file lets us reuse this from both report paths.
        procedure write_report_to_file(file f : text) is
            variable l       : line;
            variable covered : integer := 0;
        begin
            -- ---- Header ----
            write(l, string'("================================================================="));
            writeline(f, l);
            write(l, string'("  Functional Coverage Report"));
            writeline(f, l);
            write(l, string'("================================================================="));
            writeline(f, l);

            -- ---- 1D bins ----
            write(l, string'("  1D Bins"));
            writeline(f, l);
            write(l, string'("  -------"));
            writeline(f, l);
            write(l, string'("  Idx  Name                              Range            Hits   Target  OK?"));
            writeline(f, l);
            write(l, string'("  ---  --------------------------------  ---------------  -----  ------  ---"));
            writeline(f, l);

            for i in 0 to v_bin_count - 1 loop
                if v_bins(i).hits >= v_bins(i).weight then
                    covered := covered + 1;
                end if;
                write(l, string'("  "));
                write(l, i,        right, 3);
                write(l, string'("  "));
                write(l, v_bins(i).name);                     -- fixed MAX_NAME_LEN chars
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
            end loop;

            writeline(f, l);    -- blank line
            write(l, string'("  1D Coverage : ") & fmt_pct(get_coverage));
            writeline(f, l);
            writeline(f, l);

            -- ---- Cross-coverage matrix ----
            write(l, string'("  Cross-Coverage Matrix  (rows = val_a bin, cols = val_b bin)"));
            writeline(f, l);
            write(l, string'("  "));
            write(l, string'("     "));
            for j in 0 to v_bin_count - 1 loop
                write(l, j, right, 6);
            end loop;
            writeline(f, l);

            write(l, string'("  "));
            write(l, string'("  ---"));
            for j in 0 to v_bin_count - 1 loop
                write(l, string'("  ----"));
            end loop;
            writeline(f, l);

            for i in 0 to v_bin_count - 1 loop
                write(l, string'("  "));
                write(l, i, right, 3);
                write(l, string'("  "));
                for j in 0 to v_bin_count - 1 loop
                    write(l, v_cross(i, j), right, 6);
                end loop;
                writeline(f, l);
            end loop;

            writeline(f, l);
            write(l, string'("  Cross Coverage : ") & fmt_pct(get_cross_coverage));
            writeline(f, l);
            write(l, string'("================================================================="));
            writeline(f, l);
        end procedure;

        -- ----------------------------------------------------------------------
        procedure report_coverage is
            variable covered : integer := 0;
        begin
            report "=================================================================" severity note;
            report "  Functional Coverage Report" severity note;
            report "=================================================================" severity note;
            report "  1D Bins:" severity note;

            for i in 0 to v_bin_count - 1 loop
                if v_bins(i).hits >= v_bins(i).weight then
                    covered := covered + 1;
                end if;
                report "  [" & integer'image(i) & "] " &
                       v_bins(i).name &
                       "  range=[" & integer'image(v_bins(i).min) &
                       ".."        & integer'image(v_bins(i).max) & "]" &
                       "  hits="   & integer'image(v_bins(i).hits) &
                       "  target=" & integer'image(v_bins(i).weight) &
                       "  covered=" & boolean'image(v_bins(i).hits >= v_bins(i).weight)
                    severity note;
            end loop;

            report "  1D Coverage : " & fmt_pct(get_coverage) severity note;
            report "  Cross Coverage : " & fmt_pct(get_cross_coverage) severity note;

            report "  Cross Matrix (non-zero cells):" severity note;
            for i in 0 to v_bin_count - 1 loop
                for j in 0 to v_bin_count - 1 loop
                    if v_cross(i, j) > 0 then
                        report "    [" & integer'image(i) & "][" & integer'image(j) & "] = " &
                               integer'image(v_cross(i, j))
                            severity note;
                    end if;
                end loop;
            end loop;

            report "=================================================================" severity note;
        end procedure;

        -- ----------------------------------------------------------------------
        procedure write_coverage_file(filename : in string) is
            file     f      : text;
            variable status : file_open_status;
        begin
            file_open(status, f, filename, write_mode);
            assert status = open_ok
                report "coverage_pkg: cannot open file '" & filename & "'"
                severity failure;
            write_report_to_file(f);
            file_close(f);
            report "coverage_pkg: report written to '" & filename & "'" severity note;
        end procedure;

        -- ----------------------------------------------------------------------
        procedure report_all(filename : in string) is
        begin
            report_coverage;
            write_coverage_file(filename);
        end procedure;

    end protected body t_coverage;

end package body coverage_pkg;
