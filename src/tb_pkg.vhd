library ieee;
use ieee.std_logic_1164.all;
library std;
use std.textio.all;

package tb_pkg is

  type log_level_t is (DEBUG, INFO, WARNING, ERROR, FATAL);

  -- Print message with severity level and simulation timestamp to stdout.
  -- Uses writeline (std.textio) rather than report.
  -- FATAL also issues a VHDL failure to stop the simulator.
  procedure print(
    constant level : in log_level_t;
    constant msg   : in string
  );

  -- Convenience overload: defaults to INFO.
  procedure print(constant msg : in string);

  -- Drive clk with the given period. Call inside a dedicated process;
  -- the procedure loops forever.
  procedure clk_gen(
    signal   clk    : inout std_logic;
    constant period : in    time
  );

  -- Assert reset (active_level) for duration, then deassert.
  procedure reset_seq(
    signal   rst          : out std_logic;
    constant active_level : in  std_logic := '1';
    constant duration     : in  time      := 100 ns
  );

end package tb_pkg;

package body tb_pkg is

  procedure print(constant level : in log_level_t; constant msg : in string) is
    variable l : line;
  begin
    write(l, "[" & time'image(now) & "][" & log_level_t'image(level) & "] " & msg);
    writeline(output, l);
    if level = FATAL then
      report "FATAL: simulation stopped" severity failure;
    end if;
  end procedure;

  procedure print(constant msg : in string) is
  begin
    print(INFO, msg);
  end procedure;

  procedure clk_gen(signal clk : inout std_logic; constant period : in time) is
  begin
    clk <= '0';
    loop
      wait for period / 2;
      clk <= not clk;
    end loop;
  end procedure;

  procedure reset_seq(
    signal   rst          : out std_logic;
    constant active_level : in  std_logic := '1';
    constant duration     : in  time      := 100 ns
  ) is
  begin
    rst <= active_level;
    wait for duration;
    rst <= not active_level;
    wait for 0 ns;
  end procedure;

end package body tb_pkg;
