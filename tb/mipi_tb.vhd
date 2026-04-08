library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.tb_scoreboard_pkg.all;
use tb_utils.coverage_pkg.all;
use tb_utils.prng_pkg.all;
use tb_utils.mipi_csi2_pkg.all;

entity mipi_tb is
end entity mipi_tb;

architecture sim of mipi_tb is
  signal clk    : std_logic := '0';
  signal tvalid : std_logic := '0';
  signal tready : std_logic := '1';  -- loopback: always ready
  signal tdata  : std_logic_vector(7 downto 0) := (others => '0');
  signal tuser  : std_logic := '0';  -- K-char flag
  signal tlast  : std_logic := '0';

  shared variable sb         : scoreboard_t;
  shared variable rng        : rand_t;
  shared variable dt_cov     : t_coverage;
  shared variable vc_cov     : t_coverage;
  shared variable pxval_cov  : t_coverage;
  shared variable dim_cov    : t_coverage;

  type test_cfg_t is record
    dt        : std_logic_vector(5 downto 0);
    vc        : natural range 0 to 3;
    n_pixels  : positive;
    px_bits   : positive;
  end record;

  type test_cfg_arr_t is array(natural range <>) of test_cfg_t;

  constant TESTS : test_cfg_arr_t := (
    (DT_RAW8,     0, 4,  8),
    (DT_RAW10,    1, 4, 10),
    (DT_RAW12,    2, 4, 12),
    (DT_RAW14,    3, 4, 14),
    (DT_RAW16,    0, 16, 16),
    (DT_YUV422_8, 1, 16, 16),
    (DT_RGB888,   2, 16, 24),
    (DT_RAW10,    3, 64, 10),
    (DT_RAW14,    0, 64, 14)
  );

begin

  clk_proc : process
  begin
    clk_gen(clk, 10 ns);
  end process;

  writer : process
    variable payload      : std_logic_vector(64 * 24 - 1 downto 0);
    variable packed       : std_logic_vector(64 * 24 - 1 downto 0);
    variable push_buf     : std_logic_vector(64 * 24 - 1 downto 0);
    variable packed_bytes : natural;
    variable px_val  : natural;
    variable px_slv  : std_logic_vector(23 downto 0);
    variable frame   : natural := 1;
  begin
    dt_cov.set_name("dt_cov");
    dt_cov.add_bin("RAW8",     0, 0);
    dt_cov.add_bin("RAW10",    1, 1);
    dt_cov.add_bin("RAW12",    2, 2);
    dt_cov.add_bin("RAW14",    3, 3);
    dt_cov.add_bin("RAW16",    4, 4);
    dt_cov.add_bin("YUV422_8", 5, 5);
    dt_cov.add_bin("RGB888",   6, 6);

    vc_cov.set_name("vc_cov");
    vc_cov.add_bin("vc0", 0, 0);
    vc_cov.add_bin("vc1", 1, 1);
    vc_cov.add_bin("vc2", 2, 2);
    vc_cov.add_bin("vc3", 3, 3);

    pxval_cov.set_name("pxval_cov");
    pxval_cov.add_bin("range_0",    0,   31);
    pxval_cov.add_bin("range_1",   32,   63);
    pxval_cov.add_bin("range_2",   64,   95);
    pxval_cov.add_bin("range_3",   96,  127);
    pxval_cov.add_bin("range_4",  128,  159);
    pxval_cov.add_bin("range_5",  160,  191);
    pxval_cov.add_bin("range_6",  192,  223);
    pxval_cov.add_bin("range_7",  224,  255);

    dim_cov.set_name("dim_cov");
    dim_cov.add_bin("small",  0,  0);
    dim_cov.add_bin("medium", 1,  1);
    dim_cov.add_bin("large",  2,  2);

    rng.seed(42, 7);
    wait for 20 ns;

    while (not dt_cov.is_covered or not vc_cov.is_covered or
           not pxval_cov.is_covered or not dim_cov.is_covered)
          and now < 5 ms loop

      for t in TESTS'range loop
        csi2_write_short(clk, tvalid, tready, tdata, tuser, tlast,
                         DT_FRAME_START, TESTS(t).vc, frame);

        for i in 0 to TESTS(t).n_pixels - 1 loop
          px_val := (i * 7 + rng.rand_int(0, 7)) mod (2**8);
          px_slv := (others => '0');
          px_slv(TESTS(t).px_bits - 1 downto 0) :=
            std_logic_vector(to_unsigned(px_val, TESTS(t).px_bits));
          payload((TESTS(t).n_pixels - i) * TESTS(t).px_bits - 1
                  downto (TESTS(t).n_pixels - i - 1) * TESTS(t).px_bits) :=
            px_slv(TESTS(t).px_bits - 1 downto 0);
          pxval_cov.sample(px_val mod 256);
        end loop;

        case TESTS(t).dt is
          when DT_RAW8  =>
            packed(TESTS(t).n_pixels * 8 - 1 downto 0) :=
              pack_raw8(payload(TESTS(t).n_pixels * 8 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := TESTS(t).n_pixels;
          when DT_RAW10 =>
            packed((TESTS(t).n_pixels / 4) * 40 - 1 downto 0) :=
              pack_raw10(payload(TESTS(t).n_pixels * 10 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := (TESTS(t).n_pixels / 4) * 5;
          when DT_RAW12 =>
            packed((TESTS(t).n_pixels / 2) * 24 - 1 downto 0) :=
              pack_raw12(payload(TESTS(t).n_pixels * 12 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := (TESTS(t).n_pixels / 2) * 3;
          when DT_RAW14 =>
            packed((TESTS(t).n_pixels / 4) * 56 - 1 downto 0) :=
              pack_raw14(payload(TESTS(t).n_pixels * 14 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := (TESTS(t).n_pixels / 4) * 7;
          when DT_RAW16 =>
            packed(TESTS(t).n_pixels * 16 - 1 downto 0) :=
              pack_raw16(payload(TESTS(t).n_pixels * 16 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := TESTS(t).n_pixels * 2;
          when DT_YUV422_8 =>
            packed(TESTS(t).n_pixels * 16 - 1 downto 0) :=
              pack_yuv422_8(payload(TESTS(t).n_pixels * 16 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := TESTS(t).n_pixels * 2;
          when DT_RGB888 =>
            packed(TESTS(t).n_pixels * 24 - 1 downto 0) :=
              pack_rgb888(payload(TESTS(t).n_pixels * 24 - 1 downto 0), TESTS(t).n_pixels);
            packed_bytes := TESTS(t).n_pixels * 3;
          when others => null;
        end case;

        -- Align push to MSBs of push_buf so it matches the layout that
        -- csi2_read_packet uses when filling rx_payload (byte 0 at MSBs).
        push_buf := (others => '0');
        push_buf(push_buf'left downto push_buf'left - packed_bytes*8 + 1) :=
          packed(packed_bytes * 8 - 1 downto 0);
        sb.push(push_buf);

        csi2_write_long(clk, tvalid, tready, tdata, tuser, tlast,
                        TESTS(t).dt, TESTS(t).vc,
                        packed(packed_bytes * 8 - 1 downto 0));

        csi2_write_short(clk, tvalid, tready, tdata, tuser, tlast,
                         DT_FRAME_END, TESTS(t).vc, frame);

        case TESTS(t).dt is
          when DT_RAW8     => dt_cov.sample(0);
          when DT_RAW10    => dt_cov.sample(1);
          when DT_RAW12    => dt_cov.sample(2);
          when DT_RAW14    => dt_cov.sample(3);
          when DT_RAW16    => dt_cov.sample(4);
          when DT_YUV422_8 => dt_cov.sample(5);
          when DT_RGB888   => dt_cov.sample(6);
          when others      => null;
        end case;
        vc_cov.sample(TESTS(t).vc);
        case TESTS(t).n_pixels is
          when 4  => dim_cov.sample(0);
          when 16 => dim_cov.sample(1);
          when 64 => dim_cov.sample(2);
          when others => null;
        end case;

        frame := frame + 1;
      end loop;
    end loop;

    for i in 1 to 500 loop
      wait until rising_edge(clk);
      exit when sb.depth = 0;
    end loop;

    dt_cov.report_coverage;
    vc_cov.report_coverage;
    pxval_cov.report_coverage;
    dim_cov.report_coverage;

    check_true(dt_cov.is_covered,    "all data types exercised");
    check_true(vc_cov.is_covered,    "all VCs exercised");
    check_true(pxval_cov.is_covered, "pixel value range covered");
    check_true(dim_cov.is_covered,   "all frame widths exercised");
    sb.final_report;
    check_equal(sb.fail_count, 0, "no scoreboard failures");

    print(INFO, "mipi_tb: PASSED");
    std.env.stop;
  end process;

  checker : process
    variable rx_dt      : std_logic_vector(5 downto 0);
    variable rx_vc      : natural;
    variable rx_payload : std_logic_vector(64 * 24 - 1 downto 0);
    variable rx_crc_ok  : boolean;
    variable is_long    : boolean;
  begin
    loop
      csi2_read_packet(clk, tvalid, tready, tdata, tuser, tlast,
                       rx_dt, rx_vc, rx_payload, rx_crc_ok);
      is_long := (rx_dt /= DT_FRAME_START) and (rx_dt /= DT_FRAME_END) and
                 (rx_dt /= DT_LINE_START)  and (rx_dt /= DT_LINE_END);
      if is_long then
        check_true(rx_crc_ok, "CRC-16 valid on long packet");
        sb.check(rx_payload, "line payload match");
      end if;
    end loop;
  end process;

end architecture sim;
