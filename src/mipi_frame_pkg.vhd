library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
use tb_utils.mipi_csi2_pkg.all;

package mipi_frame_pkg is

  type mipi_data_type_t is (
    RAW8, RAW10, RAW12, RAW14, RAW16, YUV422_8, RGB888
  );

  type mipi_frame_cfg_t is record
    width        : positive;
    height       : positive;
    data_type    : mipi_data_type_t;
    vc           : natural range 0 to 3;
    frame_number : natural range 0 to 65535;
  end record;

  -- Drive decoded UG934 pixel AXI-Stream.
  -- tdata width (32 or 64 bit) inferred from signal. tuser=1 on first beat of frame.
  -- tlast=1 on last beat of each line. tkeep marks valid bytes in partial last beat.
  -- Pixel file: one hex pixel per line; blank lines and # comments skipped.
  procedure mipi_frame_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tkeep    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant cfg      : in  mipi_frame_cfg_t;
    constant filename : in  string
  );

  -- Drive K-char framed CSI-2 byte stream for a full frame:
  -- FS short packet, one long packet per line (packed per CSI-2 spec), FE short packet.
  procedure mipi_packet_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector(7 downto 0);
    signal   tuser    : out std_logic;
    signal   tlast    : out std_logic;
    constant cfg      : in  mipi_frame_cfg_t;
    constant filename : in  string
  );

  -- Monitor K-char framed CSI-2 byte stream from a TX DUT.
  -- Computes expected packets from cfg + filename and compares.
  -- Sets pass=false on any ECC error, CRC error, or payload mismatch.
  procedure mipi_packet_check(
    signal   clk      : in  std_logic;
    signal   tvalid   : in  std_logic;
    signal   tready   : out std_logic;
    signal   tdata    : in  std_logic_vector(7 downto 0);
    signal   tuser    : in  std_logic;
    signal   tlast    : in  std_logic;
    constant cfg      : in  mipi_frame_cfg_t;
    constant filename : in  string;
    variable pass     : out boolean
  );

end package mipi_frame_pkg;

package body mipi_frame_pkg is

  -- Return padded bits-per-pixel for UG934 bus packing.
  function px_bits_padded(dt : mipi_data_type_t) return positive is
  begin
    case dt is
      when RAW8                            => return 8;
      when RAW10 | RAW12 | RAW14 | RAW16 | YUV422_8 => return 16;
      when RGB888                          => return 32;
    end case;
  end function;

  -- Return raw (unpacked) bits per pixel for file reading.
  function px_bits_raw(dt : mipi_data_type_t) return positive is
  begin
    case dt is
      when RAW8     => return 8;
      when RAW10    => return 10;
      when RAW12    => return 12;
      when RAW14    => return 14;
      when RAW16    => return 16;
      when YUV422_8 => return 16;
      when RGB888   => return 24;
    end case;
  end function;

  -- Convert mipi_data_type_t to the 6-bit CSI-2 DT constant.
  function to_csi2_dt(dt : mipi_data_type_t) return std_logic_vector is
  begin
    case dt is
      when RAW8     => return DT_RAW8;
      when RAW10    => return DT_RAW10;
      when RAW12    => return DT_RAW12;
      when RAW14    => return DT_RAW14;
      when RAW16    => return DT_RAW16;
      when YUV422_8 => return DT_YUV422_8;
      when RGB888   => return DT_RGB888;
    end case;
  end function;

  procedure mipi_frame_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tkeep    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant cfg      : in  mipi_frame_cfg_t;
    constant filename : in  string
  ) is
    constant bus_w       : positive := tdata'length;
    constant px_padded   : positive := px_bits_padded(cfg.data_type);
    constant px_per_beat : positive := bus_w / px_padded;
    constant n_bytes     : positive := bus_w / 8;
    file     f           : text;
    variable fstatus     : file_open_status;
    variable l           : line;
    variable beat        : std_logic_vector(bus_w-1 downto 0);
    variable keep        : std_logic_vector(n_bytes-1 downto 0);
    variable px_raw      : std_logic_vector(px_bits_raw(cfg.data_type)-1 downto 0);
    variable good        : boolean;
    variable first_beat  : boolean;
    variable px_in_beat  : natural;
    variable rem_bytes   : natural;
  begin
    file_open(fstatus, f, filename, read_mode);
    assert fstatus = open_ok
      report "mipi_frame_write: cannot open " & filename severity failure;

    first_beat := true;

    for row in 0 to cfg.height-1 loop
      px_in_beat := 0;
      beat       := (others => '0');

      for col in 0 to cfg.width-1 loop
        -- Read next pixel from file (skip blank/comment lines)
        loop
          readline(f, l);
          next when l'length = 0;
          next when l'length > 0 and l(l'left) = '#';
          hread(l, px_raw, good);
          exit when good;
        end loop;

        -- Pack pixel into beat (pixel 0 at MSB of beat)
        beat((px_per_beat - px_in_beat) * px_padded - 1
             downto (px_per_beat - px_in_beat - 1) * px_padded) :=
          std_logic_vector(resize(unsigned(px_raw), px_padded));
        px_in_beat := px_in_beat + 1;

        -- Drive beat when full or end of line
        if px_in_beat = px_per_beat or col = cfg.width - 1 then
          if px_in_beat = px_per_beat then
            keep := (others => '1');
          else
            rem_bytes := (px_in_beat * px_padded + 7) / 8;
            keep := (others => '0');
            keep(n_bytes-1 downto n_bytes-rem_bytes) := (others => '1');
          end if;
          tdata  <= beat;
          tkeep  <= keep;
          tlast  <= '1' when col = cfg.width-1 else '0';
          tuser  <= '1' when (first_beat and row = 0) else '0';
          tvalid <= '1';
          wait until rising_edge(clk) and tready = '1';
          tvalid <= '0';
          tdata  <= (others => '0');
          tkeep  <= (others => '0');
          tlast  <= '0';
          tuser  <= '0';
          first_beat := false;
          beat       := (others => '0');
          px_in_beat := 0;
        end if;
      end loop;
    end loop;

    file_close(f);
    print(INFO, "mipi_frame_write: " & integer'image(cfg.width) & "x" &
                integer'image(cfg.height) & " frame sent from " & filename);
  end procedure;

  -- Read n_pixels (cfg.width) from open file f, pack per data type, return packed SLV.
  -- packed output: byte 0 at MSB (packed(n_bytes*8-1 downto n_bytes*8-8)).
  -- Caller must allocate packed large enough for the worst-case packed size.
  procedure read_and_pack_line(
    file     f              : text;
    constant cfg            : in  mipi_frame_cfg_t;
    variable packed         : out std_logic_vector;
    variable n_packed_bytes : out natural
  ) is
    constant bpp   : positive := px_bits_raw(cfg.data_type);
    variable pxbuf : std_logic_vector(cfg.width * 24 - 1 downto 0) := (others => '0');
    variable l     : line;
    variable good  : boolean;
    variable p_slv : std_logic_vector(bpp - 1 downto 0);
  begin
    for i in 0 to cfg.width - 1 loop
      loop
        readline(f, l);
        next when l'length = 0;
        next when l'length > 0 and l(l'left) = '#';
        hread(l, p_slv, good);
        exit when good;
      end loop;
      pxbuf((cfg.width - i) * bpp - 1 downto (cfg.width - i - 1) * bpp) := p_slv;
    end loop;

    case cfg.data_type is
      when RAW8 =>
        packed(cfg.width * 8 - 1 downto 0) :=
          pack_raw8(pxbuf(cfg.width * 8 - 1 downto 0), cfg.width);
        n_packed_bytes := cfg.width;
      when RAW10 =>
        packed((cfg.width / 4) * 40 - 1 downto 0) :=
          pack_raw10(pxbuf(cfg.width * 10 - 1 downto 0), cfg.width);
        n_packed_bytes := (cfg.width / 4) * 5;
      when RAW12 =>
        packed((cfg.width / 2) * 24 - 1 downto 0) :=
          pack_raw12(pxbuf(cfg.width * 12 - 1 downto 0), cfg.width);
        n_packed_bytes := (cfg.width / 2) * 3;
      when RAW14 =>
        packed((cfg.width / 4) * 56 - 1 downto 0) :=
          pack_raw14(pxbuf(cfg.width * 14 - 1 downto 0), cfg.width);
        n_packed_bytes := (cfg.width / 4) * 7;
      when RAW16 =>
        packed(cfg.width * 16 - 1 downto 0) :=
          pack_raw16(pxbuf(cfg.width * 16 - 1 downto 0), cfg.width);
        n_packed_bytes := cfg.width * 2;
      when YUV422_8 =>
        packed(cfg.width * 16 - 1 downto 0) :=
          pack_yuv422_8(pxbuf(cfg.width * 16 - 1 downto 0), cfg.width);
        n_packed_bytes := cfg.width * 2;
      when RGB888 =>
        packed(cfg.width * 24 - 1 downto 0) :=
          pack_rgb888(pxbuf(cfg.width * 24 - 1 downto 0), cfg.width);
        n_packed_bytes := cfg.width * 3;
    end case;
  end procedure;

  procedure mipi_packet_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector(7 downto 0);
    signal   tuser    : out std_logic;
    signal   tlast    : out std_logic;
    constant cfg      : in  mipi_frame_cfg_t;
    constant filename : in  string
  ) is
  file     f       : text;
  variable fstatus : file_open_status;
  -- Worst-case line payload: cfg.width * 3 bytes (RGB888)
  variable packed  : std_logic_vector(4095 * 8 - 1 downto 0) := (others => '0');
  variable n_bytes : natural;
begin
  file_open(fstatus, f, filename, read_mode);
  assert fstatus = open_ok
    report "mipi_packet_write: cannot open " & filename severity failure;

  -- Frame Start
  csi2_write_short(clk, tvalid, tready, tdata, tuser, tlast,
                   DT_FRAME_START, cfg.vc, cfg.frame_number);

  -- One long packet per line
  for row in 0 to cfg.height - 1 loop
    packed := (others => '0');
    read_and_pack_line(f, cfg, packed, n_bytes);
    csi2_write_long(clk, tvalid, tready, tdata, tuser, tlast,
                    to_csi2_dt(cfg.data_type), cfg.vc,
                    packed(n_bytes * 8 - 1 downto 0));
  end loop;

  -- Frame End
  csi2_write_short(clk, tvalid, tready, tdata, tuser, tlast,
                   DT_FRAME_END, cfg.vc, cfg.frame_number);

  file_close(f);
  print(INFO, "mipi_packet_write: " & integer'image(cfg.width) & "x" &
              integer'image(cfg.height) & " frame sent");
  end procedure;

  procedure mipi_packet_check(
    signal   clk      : in  std_logic;
    signal   tvalid   : in  std_logic;
    signal   tready   : out std_logic;
    signal   tdata    : in  std_logic_vector(7 downto 0);
    signal   tuser    : in  std_logic;
    signal   tlast    : in  std_logic;
    constant cfg      : in  mipi_frame_cfg_t;
    constant filename : in  string;
    variable pass     : out boolean
  ) is
  file     f             : text;
  variable fstatus       : file_open_status;
  variable rx_dt         : std_logic_vector(5 downto 0);
  variable rx_vc         : natural;
  variable rx_crc_ok     : boolean;
  variable rx_payload    : std_logic_vector(4095 * 8 - 1 downto 0);
  variable exp_packed    : std_logic_vector(4095 * 8 - 1 downto 0) := (others => '0');
  variable n_bytes       : natural;
  variable ok            : boolean := true;
  variable lines_checked : natural := 0;
  constant exp_dt        : std_logic_vector(5 downto 0) := to_csi2_dt(cfg.data_type);
begin
  file_open(fstatus, f, filename, read_mode);
  assert fstatus = open_ok
    report "mipi_packet_check: cannot open " & filename severity failure;

  pass := true;

  for expected_pkt in 0 to cfg.height + 1 loop
    rx_payload := (others => '0');
    csi2_read_packet(clk, tvalid, tready, tdata, tuser, tlast,
                     rx_dt, rx_vc, rx_payload, rx_crc_ok);

    if rx_dt = DT_FRAME_START then
      if rx_vc /= cfg.vc then
        print(ERROR, "mipi_packet_check: FS VC mismatch: got " & integer'image(rx_vc) &
                     " expected " & integer'image(cfg.vc));
        ok := false;
      end if;

    elsif rx_dt = DT_FRAME_END then
      if rx_vc /= cfg.vc then
        print(ERROR, "mipi_packet_check: FE VC mismatch");
        ok := false;
      end if;
      exit;

    elsif rx_dt = exp_dt then
      if not rx_crc_ok then
        print(ERROR, "mipi_packet_check: CRC error on line " & integer'image(lines_checked));
        ok := false;
      end if;
      if rx_vc /= cfg.vc then
        print(ERROR, "mipi_packet_check: VC mismatch on line " & integer'image(lines_checked));
        ok := false;
      end if;

      -- Compute expected payload from file
      exp_packed := (others => '0');
      read_and_pack_line(f, cfg, exp_packed, n_bytes);

      -- rx_payload: byte 0 at rx_payload'left (MSBs); exp_packed: byte 0 at exp_packed(n_bytes*8-1)
      if rx_payload(rx_payload'left downto rx_payload'left - n_bytes*8 + 1) /=
         exp_packed(n_bytes*8 - 1 downto 0) then
        print(ERROR, "mipi_packet_check: payload mismatch on line " &
                     integer'image(lines_checked));
        ok := false;
      end if;
      lines_checked := lines_checked + 1;

    else
      print(WARNING, "mipi_packet_check: unexpected DT=" & to_hstring(rx_dt) & ", skipping");
    end if;
  end loop;

  if lines_checked /= cfg.height then
    print(ERROR, "mipi_packet_check: expected " & integer'image(cfg.height) &
                 " data lines, got " & integer'image(lines_checked));
    ok := false;
  end if;

  file_close(f);
  pass := ok;
  if ok then
    print(INFO, "mipi_packet_check: PASS - " & integer'image(cfg.width) & "x" &
                integer'image(cfg.height) & " frame verified");
  end if;
  end procedure;

end package body mipi_frame_pkg;
