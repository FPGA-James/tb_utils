library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.tb_scoreboard_pkg.all;

entity tb_core_tb is
end entity tb_core_tb;

architecture sim of tb_core_tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '0';

  shared variable sb : scoreboard_t;
begin

  -- Clock: 10 ns period
  clk_proc : process
  begin
    clk_gen(clk, 10 ns);
  end process;

  stim : process
    variable rd : std_logic_vector(7 downto 0);
  begin
    -- Test reset_seq
    reset_seq(rst, active_level => '1', duration => 50 ns);
    check_equal(rst, '0', "rst deasserted after reset_seq");

    -- Test print at each severity
    print(DEBUG,   "debug message");
    print(INFO,    "info message");
    print(WARNING, "warning message");

    -- Test check_equal (pass)
    check_equal(x"AB", x"AB", "slv equal pass");

    -- Test check_equal (fail — expect ERROR in log, sim continues)
    check_equal(x"AB", x"CD", "slv equal fail expected");

    -- Test check_true
    check_true(true,  "true condition");
    check_true(false, "false condition - expected fail");

    -- Test integer check_equal
    check_equal(42, 42, "integer equal pass");
    check_equal(42, 99, "integer equal fail expected");

    -- Test scoreboard
    sb.push(x"AA");
    sb.push(x"BB");
    sb.check(x"AA", "scoreboard first");
    sb.check(x"CC", "scoreboard mismatch expected");  -- expected fail
    sb.check(x"BB", "scoreboard second");             -- pops BB, checks against remaining
    sb.final_report;

    wait for 100 ns;
    print(INFO, "tb_core_tb complete");
    std.env.stop;
  end process;

end architecture sim;
