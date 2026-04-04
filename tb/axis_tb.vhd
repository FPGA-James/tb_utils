library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tb_utils;
use tb_utils.tb_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.tb_scoreboard_pkg.all;
use tb_utils.axis_pkg.all;
use tb_utils.coverage_pkg.all;

entity axis_tb is
end entity axis_tb;

architecture sim of axis_tb is
  signal clk    : std_logic := '0';
  signal tvalid : std_logic := '0';
  signal tready : std_logic := '0';
  signal tdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal tlast  : std_logic := '0';

  shared variable sb        : scoreboard_t;
  shared variable data_cov  : t_coverage;  -- tdata lower/upper byte range coverage
  shared variable ctrl_cov  : t_coverage;  -- tlast state coverage
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

  -- Slave: receive 4 beats, check via scoreboard, sample coverage
  slave : process
    variable rx_data : std_logic_vector(31 downto 0);
    variable rx_last : boolean;
    variable lo_byte : integer;
    variable hi_byte : integer;
  begin
    -- Coverage bins: lower byte split at 128; cross checks lo-byte x hi-byte combination
    data_cov.add_bin("byte_lo_half",   0, 127);
    data_cov.add_bin("byte_hi_half", 128, 255);
    -- tlast: both not-last and last beats must be observed
    ctrl_cov.add_bin("not_last", 0, 0);
    ctrl_cov.add_bin("last",     1, 1);

    wait for 20 ns;
    for i in 0 to 3 loop
      axis_read(clk, tvalid, tready, tdata, tlast, rx_data, rx_last);
      sb.check(rx_data, "axis beat " & integer'image(i));
      -- Sample 1D data coverage (lower byte) and cross (lower x upper byte)
      lo_byte := to_integer(unsigned(rx_data(7  downto 0)));
      hi_byte := to_integer(unsigned(rx_data(15 downto 8)));
      data_cov.sample(lo_byte);
      data_cov.sample_cross(lo_byte, hi_byte);
      -- Sample tlast state
      if rx_last then ctrl_cov.sample(1); else ctrl_cov.sample(0); end if;
    end loop;
    -- Coverage report
    data_cov.report_coverage;
    ctrl_cov.report_coverage;
    check_true(data_cov.get_coverage = 100.0, "all data byte ranges covered");
    check_true(ctrl_cov.get_coverage = 100.0, "both tlast states covered");
    sb.final_report;
    check_equal(sb.fail_count, 0, "no scoreboard failures");
    print(INFO, "axis_tb complete");
    std.env.stop;
  end process;

end architecture sim;
