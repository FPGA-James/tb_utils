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
