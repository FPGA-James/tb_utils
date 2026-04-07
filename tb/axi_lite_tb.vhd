library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.tb_scoreboard_pkg.all;
use tb_utils.axi_lite_pkg.all;
use tb_utils.coverage_pkg.all;
use tb_utils.prng_pkg.all;

entity axi_lite_tb is
end entity axi_lite_tb;

architecture sim of axi_lite_tb is
  signal clk     : std_logic := '0';
  -- Write address
  signal awvalid : std_logic := '0';
  signal awready : std_logic := '0';
  signal awaddr  : std_logic_vector(7 downto 0)  := (others => '0');
  -- Write data
  signal wvalid  : std_logic := '0';
  signal wready  : std_logic := '0';
  signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb   : std_logic_vector(3 downto 0)  := (others => '0');
  -- Write response
  signal bvalid  : std_logic := '0';
  signal bready  : std_logic := '0';
  signal bresp   : std_logic_vector(1 downto 0)  := "00";
  -- Read address
  signal arvalid : std_logic := '0';
  signal arready : std_logic := '0';
  signal araddr  : std_logic_vector(7 downto 0)  := (others => '0');
  -- Read data
  signal rvalid  : std_logic := '0';
  signal rready  : std_logic := '0';
  signal rdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal rresp   : std_logic_vector(1 downto 0)  := "00";

  shared variable sb       : scoreboard_t;
  shared variable rng      : rand_t;
  shared variable addr_cov : t_coverage;  -- which register indices were written
  shared variable txn_cov  : t_coverage;  -- write (0) vs read (1) transaction types

  -- Simple 4-register slave model (word-addressed via bits [3:2])
  type reg_file_t is array(0 to 3) of std_logic_vector(31 downto 0);
begin

  clk_proc : process
  begin
    clk_gen(clk, 10 ns);
  end process;

  -- Minimal AXI-Lite slave (register file)
  slave : process
    variable regs : reg_file_t := (others => (others => '0'));
    variable idx  : integer;
  begin
    awready <= '0'; wready <= '0'; bvalid <= '0';
    arready <= '0'; rvalid <= '0';
    wait until rising_edge(clk);

    loop
      -- Handle write
      if awvalid = '1' then
        awready <= '1';
        wait until rising_edge(clk);
        awready <= '0';
        idx := to_integer(unsigned(awaddr(3 downto 2)));
        wait until rising_edge(clk) and wvalid = '1';
        wready <= '1';
        regs(idx) := wdata;
        wait until rising_edge(clk);
        wready <= '0';
        bvalid <= '1'; bresp <= "00";
        wait until rising_edge(clk) and bready = '1';
        bvalid <= '0';
      end if;

      -- Handle read
      if arvalid = '1' then
        arready <= '1';
        wait until rising_edge(clk);
        arready <= '0';
        idx := to_integer(unsigned(araddr(3 downto 2)));
        rdata <= regs(idx);
        rvalid <= '1'; rresp <= "00";
        wait until rising_edge(clk) and rready = '1';
        rvalid <= '0';
      end if;

      wait until rising_edge(clk);
    end loop;
  end process;

  -- Master: random writes and reads until all register addresses covered or 3 ms timeout
  master : process
    -- Shadow register file tracks what was written, for read-back verification
    variable shadow_regs : reg_file_t := (others => (others => '0'));
    variable wr_data     : std_logic_vector(31 downto 0);
    variable rd_data     : std_logic_vector(31 downto 0);
    variable widx        : integer;
    variable ridx        : integer;
    variable iter        : integer := 0;
  begin
    -- Coverage bins: register index 0-3; write (0) vs read (1)
    addr_cov.set_name("addr_cov");
    addr_cov.add_bin("reg0", 0, 0);
    addr_cov.add_bin("reg1", 1, 1);
    addr_cov.add_bin("reg2", 2, 2);
    addr_cov.add_bin("reg3", 3, 3);
    txn_cov.set_name("txn_cov");
    txn_cov.add_bin("write", 0, 0);
    txn_cov.add_bin("read",  1, 1);

    rng.seed(56, 78);
    wait for 30 ns;

    while (not addr_cov.is_covered or not txn_cov.is_covered)
          and now < 3 ms loop

      -- Write: random register index, random data
      widx    := rng.rand_int(0, 3);
      wr_data := rng.rand_slv(32);
      axi_lite_write(clk,
        awvalid, awready, awaddr,
        wvalid, wready, wdata, wstrb,
        bvalid, bready, bresp,
        std_logic_vector(to_unsigned(widx * 4, 8)),
        wr_data
      );
      shadow_regs(widx) := wr_data;
      addr_cov.sample(widx);
      txn_cov.sample(0);

      -- Read: random register index, verify against shadow
      ridx := rng.rand_int(0, 3);
      sb.push(shadow_regs(ridx));
      axi_lite_read(clk,
        arvalid, arready, araddr,
        rvalid, rready, rdata, rresp,
        std_logic_vector(to_unsigned(ridx * 4, 8)),
        rd_data
      );
      sb.check(rd_data, "reg " & integer'image(ridx));
      addr_cov.sample(ridx);
      txn_cov.sample(1);

      iter := iter + 1;
    end loop;

    -- Coverage and correctness report
    addr_cov.report_coverage;
    txn_cov.report_coverage;
    if now >= 3 ms then
      print(WARNING, "axi_lite_tb: 3 ms timeout - uncovered: addr=" & addr_cov.get_uncovered &
                     " txn=" & txn_cov.get_uncovered);
    end if;
    check_true(addr_cov.is_covered, "all register addresses accessed");
    check_true(txn_cov.is_covered,  "both write and read transactions seen");
    sb.final_report;
    check_equal(sb.fail_count, 0, "no scoreboard failures");
    print(INFO, "axi_lite_tb: " & integer'image(iter) &
                " iterations, finished at " & time'image(now));
    std.env.stop;
  end process;

end architecture sim;
