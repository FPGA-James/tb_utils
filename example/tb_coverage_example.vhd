-- =============================================================================
-- tb_coverage_example.vhd
-- Example testbench demonstrating coverage_pkg:
--   - Weighted bins
--   - Per-bin hit counts
--   - Cross-coverage (two signals)
--   - Directed-random stimulus loop until coverage goals met
--   - Report via 'report' and to file
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.coverage_pkg.all;

entity tb_coverage_example is
end entity;

architecture sim of tb_coverage_example is

    -- -------------------------------------------------------------------------
    -- DUT signals (simple 8-bit adder stand-in)
    -- -------------------------------------------------------------------------
    signal clk    : std_logic := '0';
    signal a_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal b_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal sum_out : std_logic_vector(8 downto 0);     -- 9-bit to hold carry

    -- -------------------------------------------------------------------------
    -- Shared coverage collector
    -- -------------------------------------------------------------------------
    shared variable cov : t_coverage;

    -- Coverage goals
    constant GOAL_1D    : real := 100.0;
    constant GOAL_CROSS : real := 80.0;   -- 80% cross-coverage is acceptable

    -- -------------------------------------------------------------------------
    -- Random helpers (Wichmann-Hill via ieee.math_real)
    -- -------------------------------------------------------------------------
    procedure rand_int (
        min, max        : in  integer;
        variable s1, s2 : inout positive;
        variable result : out  integer
    ) is
        variable r : real;
    begin
        uniform(s1, s2, r);
        result := min + integer(r * real(max - min + 1));
        -- Clamp: uniform can theoretically return exactly 1.0
        if result > max then result := max; end if;
    end procedure;

begin

    -- -------------------------------------------------------------------------
    -- Clock: 10 ns period
    -- -------------------------------------------------------------------------
    clk <= not clk after 5 ns;

    -- -------------------------------------------------------------------------
    -- Trivial DUT (replace with your real component)
    -- -------------------------------------------------------------------------
    sum_out <= std_logic_vector(
        unsigned('0' & a_in) + unsigned('0' & b_in)
    );

    -- =========================================================================
    -- Coverage setup + directed-random stimulus
    -- =========================================================================
    stimulus : process
        variable s1, s2   : positive := 1;
        variable rand_a   : integer;
        variable rand_b   : integer;
        variable itr      : integer  := 0;
        constant MAX_ITER : integer  := 100_000;
    begin

        -- --------------------------------------------------------------------
        -- Define bins for operand A / B (same bins apply to both)
        --
        -- Weighted bins: corner cases need more hits to reduce the chance
        -- they were sampled by accident rather than exercised thoroughly.
        --
        --   Bin name         Range        Weight (target hits)
        -- --------------------------------------------------------------------
        cov.add_bin("zero",         0,    0,   weight => 5);   -- exact 0, hit 5x
        cov.add_bin("low",          1,   31,   weight => 3);   -- low values
        cov.add_bin("mid-low",     32,   63,   weight => 2);
        cov.add_bin("mid-high",    64,   95,   weight => 2);
        cov.add_bin("high",        96,  254,   weight => 3);   -- high values
        cov.add_bin("max",        255,  255,   weight => 5);   -- exact 255, hit 5x

        report "Coverage bins defined: " &
               integer'image(cov.get_bin_count) severity note;

        -- --------------------------------------------------------------------
        -- Directed-random loop: keep going until both goals are satisfied
        -- --------------------------------------------------------------------
        while (cov.get_coverage       < GOAL_1D    or
               cov.get_cross_coverage < GOAL_CROSS)
              and itr < MAX_ITER loop

            -- Generate random operands
            rand_int(0, 255, s1, s2, rand_a);
            rand_int(0, 255, s1, s2, rand_b);

            -- Drive DUT
            a_in <= std_logic_vector(to_unsigned(rand_a, 8));
            b_in <= std_logic_vector(to_unsigned(rand_b, 8));
            wait until rising_edge(clk);

            -- Sample 1D coverage for both operands independently
            cov.sample(rand_a);
            cov.sample(rand_b);

            -- Sample cross-coverage: which (bin_a, bin_b) pair was exercised
            cov.sample_cross(rand_a, rand_b);

            itr := itr + 1;
        end loop;

        -- --------------------------------------------------------------------
        -- Optional: inject directed corner cases to guarantee weight targets
        -- on zero/max bins (useful if random sampling is slow to hit them)
        -- --------------------------------------------------------------------
        for pass in 1 to 5 loop
            a_in <= (others => '0');    -- 0
            b_in <= (others => '1');    -- 255
            wait until rising_edge(clk);
            cov.sample(0);
            cov.sample(255);
            cov.sample_cross(0, 255);

            a_in <= (others => '1');    -- 255
            b_in <= (others => '0');    -- 0
            wait until rising_edge(clk);
            cov.sample(255);
            cov.sample(0);
            cov.sample_cross(255, 0);
        end loop;

        -- --------------------------------------------------------------------
        -- Final report
        -- --------------------------------------------------------------------
        report "Stimulus complete after " & integer'image(itr) &
               " random iterations." severity note;

        -- Prints to simulator console + writes coverage_report.txt
        cov.report_all("coverage_report.txt");

        -- Fail the simulation if 1D coverage is not 100%
        assert cov.get_coverage = 100.0
            report "1D coverage goal NOT met: " &
                   real'image(cov.get_coverage) & " %"
            severity failure;

        -- Warn (not fail) if cross-coverage goal is not met
        assert cov.get_cross_coverage >= GOAL_CROSS
            report "Cross-coverage goal NOT met: " &
                   real'image(cov.get_cross_coverage) & " %"
            severity warning;

        std.env.stop;   -- VHDL-2008 clean stop
    end process;

end architecture sim;
