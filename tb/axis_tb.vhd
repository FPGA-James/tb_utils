library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.tb_scoreboard_pkg.all;
use tb_utils.axis_pkg.all;

entity axis_tb is
end entity axis_tb;

architecture sim of axis_tb is
  signal clk    : std_logic := '0';
  signal tvalid : std_logic := '0';
  signal tready : std_logic := '0';
  signal tdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal tlast  : std_logic := '0';

  shared variable sb : scoreboard_t;
begin

  clk_proc : process
  begin
    clk_gen(clk, 10 ns);
  end process;

  -- Master: pre-load scoreboard then send 4 beats
  master : process
  begin
    -- Push all expected values before driving so slave never races ahead of the queue
    sb.push(x"DEADBEEF");
    sb.push(x"CAFEBABE");
    sb.push(x"12345678");
    sb.push(x"AABBCCDD");
    wait for 20 ns;
    axis_write(clk, tvalid, tready, tdata, tlast, x"DEADBEEF", last => false);
    axis_write(clk, tvalid, tready, tdata, tlast, x"CAFEBABE", last => false);
    axis_write(clk, tvalid, tready, tdata, tlast, x"12345678", last => false);
    axis_write(clk, tvalid, tready, tdata, tlast, x"AABBCCDD", last => true);
    wait;
  end process;

  -- Slave: receive 4 beats and check via scoreboard
  slave : process
    variable rx_data : std_logic_vector(31 downto 0);
    variable rx_last : boolean;
  begin
    wait for 20 ns;
    for i in 0 to 3 loop
      axis_read(clk, tvalid, tready, tdata, tlast, rx_data, rx_last);
      sb.check(rx_data, "axis beat " & integer'image(i));
    end loop;
    sb.final_report;
    check_equal(sb.fail_count, 0, "no scoreboard failures");
    print(INFO, "axis_tb complete");
    std.env.stop;
  end process;

end architecture sim;
