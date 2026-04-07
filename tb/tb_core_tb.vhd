library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
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
    reset_seq(rst, clk, active_level => '1', cycles => 5);
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

    -- Scoreboard: std_logic_vector (type mark required — x"" literals are ambiguous with string)
    sb.push(std_logic_vector'(x"AA"));
    sb.push(std_logic_vector'(x"BB"));
    sb.check(std_logic_vector'(x"AA"), "scoreboard slv pass");
    sb.check(std_logic_vector'(x"CC"), "scoreboard slv mismatch expected");  -- expected fail
    sb.check(std_logic_vector'(x"BB"), "scoreboard slv second");
    sb.final_report;

    -- Scoreboard: integer
    sb.push(42);
    sb.push(100);
    sb.check(42,  "scoreboard int pass");
    sb.check(99,  "scoreboard int mismatch expected");    -- expected fail
    sb.check(100, "scoreboard int second");
    sb.final_report;

    -- Scoreboard: std_logic
    sb.push('1');
    sb.push('0');
    sb.check('1', "scoreboard sl pass");
    sb.check('0', "scoreboard sl second");
    sb.final_report;

    -- Scoreboard: string (type mark required — string literals are ambiguous with std_logic_vector)
    sb.push(string'("hello"));
    sb.push(string'("world"));
    sb.check(string'("hello"), "scoreboard str pass");
    sb.check(string'("wrong"), "scoreboard str mismatch expected");  -- expected fail
    sb.check(string'("world"), "scoreboard str second");
    sb.final_report;

    wait for 100 ns;
    print(INFO, "tb_core_tb complete");
    std.env.stop;
  end process;

end architecture sim;
