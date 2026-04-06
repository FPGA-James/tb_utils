-- =============================================================================
-- crv_axi_lite_tb.vhd
-- Constrained Random Verification showcase for AXI-Lite
--
-- Two-phase strategy:
--   Phase 1 — Directed:  t_sequence (WALK1) writes to all 4 registers.
--             Establishes shadow state; only hits data_cov["low"] range.
--   Phase 2 — CRV:       rand_cov_point targets remaining data bins (mid/high).
--             t_flow_controller (THROTTLE) decides write vs read each iteration.
--             t_flow_controller (RANDOM) injects inter-transaction gaps.
--             Scoreboard verifies every read against shadow register file.
--
-- Coverage closure required:
--   addr_cov  — each register index 0..3, weight=2 (needs write + read)
--   data_cov  — MSB quadrants of 32-bit write data (plus illegal 0xFF)
--   txn_cov   — write (0) and read (1) transaction types
-- =============================================================================

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
use tb_utils.flow_ctrl_pkg.all;
use tb_utils.sequence_pkg.all;

entity crv_axi_lite_tb is
end entity crv_axi_lite_tb;

architecture sim of crv_axi_lite_tb is

  signal clk     : std_logic := '0';
  signal awvalid : std_logic := '0';
  signal awready : std_logic := '0';
  signal awaddr  : std_logic_vector(7 downto 0)  := (others => '0');
  signal wvalid  : std_logic := '0';
  signal wready  : std_logic := '0';
  signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb   : std_logic_vector(3 downto 0)  := (others => '0');
  signal bvalid  : std_logic := '0';
  signal bready  : std_logic := '0';
  signal bresp   : std_logic_vector(1 downto 0)  := "00";
  signal arvalid : std_logic := '0';
  signal arready : std_logic := '0';
  signal araddr  : std_logic_vector(7 downto 0)  := (others => '0');
  signal rvalid  : std_logic := '0';
  signal rready  : std_logic := '0';
  signal rdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal rresp   : std_logic_vector(1 downto 0)  := "00";

  shared variable sb       : scoreboard_t;
  shared variable rng      : rand_t;
  shared variable seq      : t_sequence;
  shared variable fc_txn   : t_flow_controller;  -- write vs read decision
  shared variable fc_gap   : t_flow_controller;  -- inter-transaction gaps
  shared variable addr_cov : t_coverage;
  shared variable data_cov : t_coverage;
  shared variable txn_cov  : t_coverage;

  type reg_file_t is array(0 to 3) of std_logic_vector(31 downto 0);

begin

  clk_proc : process
  begin
    clk_gen(clk, 10 ns);
  end process;

  -- Simple 4-register slave (word-addressed via bits [3:2])
  slave : process
    variable regs : reg_file_t := (others => (others => '0'));
    variable idx  : integer;
  begin
    awready <= '0'; wready <= '0'; bvalid <= '0';
    arready <= '0'; rvalid <= '0';
    wait until rising_edge(clk);
    loop
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

  -- ==========================================================================
  -- Master: directed phase then CRV phase
  -- ==========================================================================
  master : process
    variable shadow   : reg_file_t := (others => (others => '0'));
    variable wr_data  : std_logic_vector(31 downto 0);
    variable rd_data  : std_logic_vector(31 downto 0);
    variable widx     : integer;
    variable ridx     : integer;
    variable hbyte    : integer;
    variable iter_d   : integer := 0;
    variable iter_crv : integer := 0;
  begin

    -- ---- Coverage setup -----------------------------------------------------
    -- addr_cov: weight=2 so each register needs both a write hit and a read hit
    addr_cov.set_name("addr_cov");
    addr_cov.add_bin("reg0", 0, 0, 2);
    addr_cov.add_bin("reg1", 1, 1, 2);
    addr_cov.add_bin("reg2", 2, 2, 2);
    addr_cov.add_bin("reg3", 3, 3, 2);

    -- data_cov: MSB quadrants of write data.  0xFF is illegal (reserved).
    data_cov.set_name("data_cov");
    data_cov.add_bin("zero",     0,   0);    -- high byte 0x00
    data_cov.add_bin("low",      1,  63);    -- high byte 0x01-0x3F
    data_cov.add_bin("mid",     64, 191);    -- high byte 0x40-0xBF
    data_cov.add_bin("high",   192, 254);    -- high byte 0xC0-0xFE
    data_cov.add_illegal_bin("all_ones", 255, 255);  -- 0xFF reserved

    txn_cov.set_name("txn_cov");
    txn_cov.add_bin("write", 0, 0);
    txn_cov.add_bin("read",  1, 1);

    -- ---- Flow controller setup ----------------------------------------------
    -- fc_txn: THROTTLE 60% -> write 60% of iterations, read 40%
    fc_txn.set_mode("THROTTLE");
    fc_txn.set_throttle(60);

    -- fc_gap: RANDOM 80% -> no gap 80% of iterations, 1-cycle gap 20%
    fc_gap.set_mode("RANDOM");
    fc_gap.set_throttle(80);

    -- ---- Sequence setup for directed phase ----------------------------------
    -- WALK1 through the high byte: 1 -> 2 -> 4 -> 8
    -- All values land in data_cov["low"], leaving mid/high/zero for CRV.
    seq.set_mode("WALK1");
    seq.set_width(8);
    seq.set_range(1, 128);

    rng.seed(77, 13);
    wait for 30 ns;

    -- ==========================================================================
    -- Phase 1: Directed — walking-ones writes to all 4 registers
    -- ==========================================================================
    print(INFO, "crv_axi_lite_tb: --- Phase 1: Directed ---");

    for i in 0 to 3 loop
      -- High byte is walking-ones (1,2,4,8); low 24-bits are random
      hbyte   := seq.next_val;
      wr_data := std_logic_vector(to_unsigned(hbyte, 8)) & rng.rand_slv(24);

      axi_lite_write(clk,
        awvalid, awready, awaddr,
        wvalid, wready, wdata, wstrb,
        bvalid, bready, bresp,
        std_logic_vector(to_unsigned(i * 4, 8)), wr_data);

      shadow(i) := wr_data;
      addr_cov.sample(i);
      data_cov.sample(hbyte);
      txn_cov.sample(0);

      -- Random inter-transaction gap (flow control)
      if not fc_gap.ready_this_cycle then
        wait until rising_edge(clk);
      end if;

      iter_d := iter_d + 1;
    end loop;

    print(INFO, "crv_axi_lite_tb: directed phase done, " &
                integer'image(iter_d) & " writes" &
                " | addr=" & addr_cov.get_uncovered &
                " | data=" & data_cov.get_uncovered &
                " | txn="  & txn_cov.get_uncovered);

    -- ==========================================================================
    -- Phase 2: CRV — coverage-directed stimulus until closure or 3 ms timeout
    -- ==========================================================================
    print(INFO, "crv_axi_lite_tb: --- Phase 2: CRV ---");

    while (not addr_cov.is_covered or
           not data_cov.is_covered or
           not txn_cov.is_covered)
          and now < 3 ms loop

      -- Flow control: random gap before transaction
      if not fc_gap.ready_this_cycle then
        wait until rising_edge(clk);
      end if;

      if fc_txn.ready_this_cycle then
        -- ---- Write transaction ----------------------------------------------
        -- rand_cov_point on addr_cov targets the least-covered register
        widx  := addr_cov.rand_cov_point(rng.rand_int(0, 999),
                                          rng.rand_int(0, 3));

        -- rand_cov_point on data_cov targets uncovered high-byte quadrant
        hbyte   := data_cov.rand_cov_point(rng.rand_int(0, 999),
                                            rng.rand_int(0, 254));
        wr_data := std_logic_vector(to_unsigned(hbyte, 8)) & rng.rand_slv(24);

        axi_lite_write(clk,
          awvalid, awready, awaddr,
          wvalid, wready, wdata, wstrb,
          bvalid, bready, bresp,
          std_logic_vector(to_unsigned(widx * 4, 8)), wr_data);

        shadow(widx) := wr_data;
        addr_cov.sample(widx);
        data_cov.sample(hbyte);
        txn_cov.sample(0);

      else
        -- ---- Read transaction -----------------------------------------------
        -- rand_cov_point on addr_cov targets the least-read register
        ridx := addr_cov.rand_cov_point(rng.rand_int(0, 999),
                                         rng.rand_int(0, 3));

        -- Push expected value to scoreboard before driving the read
        sb.push(shadow(ridx));

        axi_lite_read(clk,
          arvalid, arready, araddr,
          rvalid, rready, rdata, rresp,
          std_logic_vector(to_unsigned(ridx * 4, 8)), rd_data);

        sb.check(rd_data, "reg " & integer'image(ridx));
        addr_cov.sample(ridx);
        txn_cov.sample(1);

      end if;

      iter_crv := iter_crv + 1;
    end loop;

    -- ==========================================================================
    -- Reports and checks
    -- ==========================================================================
    addr_cov.report_coverage;
    data_cov.report_coverage;
    txn_cov.report_coverage;

    if now >= 3 ms then
      print(WARNING, "crv_axi_lite_tb: 3 ms timeout - uncovered:" &
                     " addr=" & addr_cov.get_uncovered &
                     " data=" & data_cov.get_uncovered &
                     " txn="  & txn_cov.get_uncovered);
    end if;

    check_true(addr_cov.is_covered, "all registers both written and read (weight=2)");
    check_true(data_cov.is_covered, "all data high-byte quadrants covered");
    check_true(txn_cov.is_covered,  "both write and read transactions exercised");
    sb.final_report;
    check_equal(sb.fail_count, 0, "no scoreboard failures");

    print(INFO, "crv_axi_lite_tb: directed=" & integer'image(iter_d) &
                " CRV=" & integer'image(iter_crv) &
                " total=" & integer'image(iter_d + iter_crv) &
                " finished at " & time'image(now));
    std.env.stop;
  end process;

end architecture sim;
