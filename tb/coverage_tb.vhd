library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.coverage_pkg.all;

entity coverage_tb is
end entity coverage_tb;

architecture sim of coverage_tb is
  shared variable cov : t_coverage;
begin

  stim : process
  begin
    -- set_name: must not crash; name appears in report_coverage output
    cov.set_name("test_cov");

    -- ---------------------------------------------------------------
    -- 1D bins: initial state
    -- ---------------------------------------------------------------
    cov.add_bin("low",  0,   49);
    cov.add_bin("mid",  50,  99);
    cov.add_bin("high", 100, 127);

    check_equal(cov.get_bin_count, 3, "three bins defined");
    check_true(not cov.is_covered,       "not covered before sampling");
    check_true(cov.get_coverage = 0.0,   "0% before sampling");

    -- ---------------------------------------------------------------
    -- Partial coverage: only 'low' bin hit
    -- ---------------------------------------------------------------
    for i in 0 to 49 loop cov.sample(i); end loop;

    check_true(not cov.is_covered,                "not covered with only low hit");
    check_true(cov.get_uncovered = "mid, high",   "get_uncovered lists mid and high");

    -- ---------------------------------------------------------------
    -- Full coverage
    -- ---------------------------------------------------------------
    cov.sample(75);   -- mid
    cov.sample(110);  -- high

    check_true(cov.is_covered,                 "covered after all bins sampled");
    check_true(cov.get_coverage = 100.0,       "100% when all bins covered");
    check_true(cov.get_uncovered = "none",     "get_uncovered = none when covered");

    -- ---------------------------------------------------------------
    -- reset: clears hits, preserves bin definitions
    -- ---------------------------------------------------------------
    cov.reset;

    check_equal(cov.get_bin_count, 3,        "bin count preserved after reset");
    check_true(not cov.is_covered,           "not covered after reset");
    check_true(cov.get_coverage = 0.0,       "0% after reset");
    check_true(cov.get_uncovered = "low, mid, high",
                                             "all bins uncovered after reset");

    -- ---------------------------------------------------------------
    -- Illegal bins: excluded from coverage %, fire [error] on sample
    -- ---------------------------------------------------------------
    cov.add_illegal_bin("reserved", 255, 255);
    check_equal(cov.get_bin_count, 4,        "bin count includes illegal bin");

    -- Cover the three normal bins (illegal still unhit)
    cov.sample(10); cov.sample(75); cov.sample(110);

    check_true(cov.is_covered,               "is_covered ignores illegal bin");
    check_true(cov.get_coverage = 100.0,     "100% does not count illegal bin");
    check_true(cov.get_uncovered = "none",   "get_uncovered ignores illegal bin");

    -- Sample the illegal bin: prints [error], must not affect coverage %
    cov.sample(255);

    check_true(cov.get_coverage = 100.0,     "coverage unaffected by illegal hit");

    -- Out-of-range sample: silently ignored
    cov.sample(200);
    check_true(cov.get_coverage = 100.0,     "out-of-range sample ignored");

    -- ---------------------------------------------------------------
    -- Report (name and illegal bin section visible in log)
    -- ---------------------------------------------------------------
    cov.report_coverage;

    print(INFO, "coverage_tb complete");
    std.env.stop;
  end process;

end architecture sim;
