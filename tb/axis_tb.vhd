library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.tb_scoreboard_pkg.all;
use tb_utils.axis_pkg.all;
use tb_utils.coverage_pkg.all;
use tb_utils.prng_pkg.all;

entity axis_tb is
end entity axis_tb;

architecture sim of axis_tb is
  signal clk    : std_logic := '0';
  signal tvalid : std_logic := '0';
  signal tready : std_logic := '0';
  signal tdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal tlast  : std_logic := '0';

  shared variable sb       : scoreboard_t;
  shared variable rng      : rand_t;
  shared variable data_cov : t_coverage;  -- lower-byte range coverage + cross with upper byte
  shared variable ctrl_cov : t_coverage;  -- tlast state coverage
begin

  clk_proc : process
  begin
    clk_gen(clk, 10 ns);
  end process;

  -- Master: drive random packets until all coverage bins hit or 3 ms timeout
  master : process
    constant MAX_PKT_LEN : integer := 4;
    type slv32_arr_t is array(0 to MAX_PKT_LEN - 1) of std_logic_vector(31 downto 0);
    variable pkt_data : slv32_arr_t;
    variable pkt_len  : integer;
    variable lo, hi   : integer;
    variable iter     : integer := 0;
  begin
    -- 8 lower-byte bins give meaningful cross-coverage density with random data
    data_cov.set_name("data_cov");
    data_cov.add_bin("byte_0_31",    0,   31);
    data_cov.add_bin("byte_32_63",   32,  63);
    data_cov.add_bin("byte_64_95",   64,  95);
    data_cov.add_bin("byte_96_127",  96,  127);
    data_cov.add_bin("byte_128_159", 128, 159);
    data_cov.add_bin("byte_160_191", 160, 191);
    data_cov.add_bin("byte_192_223", 192, 223);
    data_cov.add_bin("byte_224_255", 224, 255);
    ctrl_cov.set_name("ctrl_cov");
    ctrl_cov.add_bin("not_last", 0, 0);
    ctrl_cov.add_bin("last",     1, 1);

    rng.seed(12, 34);
    wait for 20 ns;

    while (not data_cov.is_covered or not ctrl_cov.is_covered)
          and now < 3 ms loop

      pkt_len := rng.rand_int(1, MAX_PKT_LEN);

      -- Pre-push all beats to scoreboard before driving any, avoiding race with slave
      for b in 0 to pkt_len - 1 loop
        pkt_data(b) := rng.rand_slv(32);
        sb.push(pkt_data(b));
      end loop;

      -- Drive the packet beat by beat
      for b in 0 to pkt_len - 1 loop
        axis_write(clk, tvalid, tready, tdata, tlast,
                   pkt_data(b), last => b = pkt_len - 1);
        lo := to_integer(unsigned(pkt_data(b)(7  downto 0)));
        hi := to_integer(unsigned(pkt_data(b)(15 downto 8)));
        data_cov.sample(lo);
        data_cov.sample_cross(lo, hi);
        if b = pkt_len - 1 then ctrl_cov.sample(1); else ctrl_cov.sample(0); end if;
      end loop;

      iter := iter + 1;
    end loop;

    -- Poll until scoreboard is drained (slave finishes checking in-flight beats)
    for i in 1 to 200 loop
      wait until rising_edge(clk);
      exit when sb.depth = 0;
    end loop;

    -- Coverage and correctness report
    data_cov.report_coverage;
    ctrl_cov.report_coverage;
    if now >= 3 ms then
      print(WARNING, "axis_tb: 3 ms timeout - uncovered: data=" & data_cov.get_uncovered &
                     " ctrl=" & ctrl_cov.get_uncovered);
    end if;
    check_true(data_cov.is_covered, "all data byte bins covered");
    check_true(ctrl_cov.is_covered, "both tlast states covered");
    sb.final_report;
    check_equal(sb.fail_count, 0, "no scoreboard failures");
    print(INFO, "axis_tb: " & integer'image(iter) &
                " packets sent, finished at " & time'image(now));
    std.env.stop;
  end process;

  -- Slave: check every beat against scoreboard; runs until env.stop
  slave : process
    variable rx_data : std_logic_vector(31 downto 0);
    variable rx_last : boolean;
  begin
    loop
      axis_read(clk, tvalid, tready, tdata, tlast, rx_data, rx_last);
      sb.check(rx_data, "axis beat");
    end loop;
  end process;

end architecture sim;
