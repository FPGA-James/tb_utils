library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;

package mipi_csi2_pkg is

  -- Short-packet data type codes (6-bit)
  constant DT_FRAME_START : std_logic_vector(5 downto 0) := "000000";
  constant DT_FRAME_END   : std_logic_vector(5 downto 0) := "000001";
  constant DT_LINE_START  : std_logic_vector(5 downto 0) := "000010";
  constant DT_LINE_END    : std_logic_vector(5 downto 0) := "000011";

  -- Long-packet data type codes (6-bit)
  constant DT_RAW8     : std_logic_vector(5 downto 0) := "101010";
  constant DT_RAW10    : std_logic_vector(5 downto 0) := "101011";
  constant DT_RAW12    : std_logic_vector(5 downto 0) := "101100";
  constant DT_RAW14    : std_logic_vector(5 downto 0) := "101101";
  constant DT_RAW16    : std_logic_vector(5 downto 0) := "101110";
  constant DT_YUV422_8 : std_logic_vector(5 downto 0) := "011110";
  constant DT_RGB888   : std_logic_vector(5 downto 0) := "100100";

  -- K-character values (post-8b/10b decode)
  constant K_SOP  : std_logic_vector(7 downto 0) := x"FB";  -- K27.7
  constant K_EOP  : std_logic_vector(7 downto 0) := x"FD";  -- K29.7
  constant K_IDLE : std_logic_vector(7 downto 0) := x"BC";  -- K28.5

  -- Pixel packing functions (exposed for use by mipi_frame_pkg)
  -- Pixel 0 at MSB of input SLV; n_pixels must satisfy packing constraints.
  -- RAW10, RAW14: n_pixels must be a multiple of 4.
  -- RAW12:        n_pixels must be even.
  -- All others:   any positive n_pixels.

  -- RAW8: 1 byte/pixel. Input: n_pixels*8 bits. Output: n_pixels*8 bits.
  function pack_raw8(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- RAW10: 4 pixels -> 5 bytes. Input: n_pixels*10 bits. Output: n_pixels/4*40 bits.
  function pack_raw10(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- RAW12: 2 pixels -> 3 bytes. Input: n_pixels*12 bits. Output: n_pixels/2*24 bits.
  function pack_raw12(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- RAW14: 4 pixels -> 7 bytes. Input: n_pixels*14 bits. Output: n_pixels/4*56 bits.
  function pack_raw14(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- RAW16: 2 bytes/pixel, LSB first. Input: n_pixels*16 bits. Output: n_pixels*16 bits.
  function pack_raw16(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- YUV422_8: 2 bytes/pixel (Y+UV interleaved). Input: n_pixels*16 bits. Output: n_pixels*16 bits.
  function pack_yuv422_8(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- RGB888: 3 bytes/pixel (R,G,B). Input: n_pixels*24 bits. Output: n_pixels*24 bits.
  function pack_rgb888(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector;

  -- Procedures
  -- Link-layer AXI-Stream: tdata=8-bit decoded byte, tuser='1' for K-char.
  -- Each packet: [K_SOP,tuser=1] [bytes,tuser=0] [K_EOP,tuser=1,tlast=1]

  -- Drive one K-char framed short packet (4-byte header + ECC, no payload/CRC).
  -- word_count = frame number (FS/FE) or line number (LS/LE).
  procedure csi2_write_short(
    signal   clk        : in  std_logic;
    signal   tvalid     : out std_logic;
    signal   tready     : in  std_logic;
    signal   tdata      : out std_logic_vector(7 downto 0);
    signal   tuser      : out std_logic;
    signal   tlast      : out std_logic;
    constant data_type  : in  std_logic_vector(5 downto 0);
    constant vc         : in  natural range 0 to 3;
    constant word_count : in  natural
  );

  -- Drive one K-char framed long packet (header + ECC + payload bytes + CRC-16).
  -- payload is already-packed CSI-2 bytes for one line (use pack_* functions).
  -- payload'length must be a multiple of 8 (whole bytes).
  procedure csi2_write_long(
    signal   clk       : in  std_logic;
    signal   tvalid    : out std_logic;
    signal   tready    : in  std_logic;
    signal   tdata     : out std_logic_vector(7 downto 0);
    signal   tuser     : out std_logic;
    signal   tlast     : out std_logic;
    constant data_type : in  std_logic_vector(5 downto 0);
    constant vc        : in  natural range 0 to 3;
    constant payload   : in  std_logic_vector
  );

  -- Monitor one K-char framed packet. Skips K_IDLE bytes. Syncs on K_SOP.
  -- crc_ok is always true for short packets (no CRC).
  procedure csi2_read_packet(
    signal   clk       : in  std_logic;
    signal   tvalid    : in  std_logic;
    signal   tready    : out std_logic;
    signal   tdata     : in  std_logic_vector(7 downto 0);
    signal   tuser     : in  std_logic;
    signal   tlast     : in  std_logic;
    variable data_type : out std_logic_vector(5 downto 0);
    variable vc        : out natural;
    variable payload   : out std_logic_vector;
    variable crc_ok    : out boolean
  );

end package mipi_csi2_pkg;

package body mipi_csi2_pkg is

  -- Internal: MIPI CSI-2 ECC (Hamming code, Table 4-1)
  function csi2_ecc(b0, b1, b2 : std_logic_vector(7 downto 0))
    return std_logic_vector is
    variable d : std_logic_vector(23 downto 0);
    variable e : std_logic_vector(7 downto 0) := (others => '0');
  begin
    d := b2 & b1 & b0;
    e(0) := d(0) xor d(1) xor d(2) xor d(4) xor d(5) xor d(7)  xor
            d(10) xor d(11) xor d(13) xor d(16) xor d(20) xor d(21) xor d(22) xor d(23);
    e(1) := d(0) xor d(1) xor d(3) xor d(4) xor d(6) xor d(8)  xor
            d(10) xor d(12) xor d(14) xor d(17) xor d(20) xor d(21) xor d(22) xor d(23);
    e(2) := d(0) xor d(2) xor d(3) xor d(5) xor d(6) xor d(9)  xor
            d(11) xor d(12) xor d(15) xor d(18) xor d(20) xor d(21) xor d(22) xor d(23);
    e(3) := d(1) xor d(2) xor d(3) xor d(7) xor d(8) xor d(9)  xor
            d(13) xor d(14) xor d(15) xor d(19) xor d(20) xor d(21) xor d(22) xor d(23);
    e(4) := d(4) xor d(5) xor d(6) xor d(7) xor d(8) xor d(9)  xor
            d(16) xor d(17) xor d(18) xor d(19) xor d(20) xor d(21) xor d(22) xor d(23);
    e(5) := d(10) xor d(11) xor d(12) xor d(13) xor d(14) xor d(15) xor
            d(16) xor d(17) xor d(18) xor d(19) xor d(20) xor d(21) xor d(22) xor d(23);
    e(6) := '0';
    e(7) := '0';
    return e;
  end function;

  -- Internal: CRC-16/CCITT (poly=0x1021, init=0xFFFF)
  function csi2_crc16(data : std_logic_vector) return std_logic_vector is
    variable crc     : std_logic_vector(15 downto 0) := x"FFFF";
    variable byte_v  : std_logic_vector(7 downto 0);
    variable topbit  : std_logic;
    variable n_bytes : natural;
  begin
    n_bytes := data'length / 8;
    for i in 0 to n_bytes - 1 loop
      byte_v := data(data'left - i*8 downto data'left - i*8 - 7);
      for j in 7 downto 0 loop
        topbit := crc(15);
        crc    := crc(14 downto 0) & '0';
        if (topbit xor byte_v(j)) = '1' then
          crc := crc xor x"1021";
        end if;
      end loop;
    end loop;
    return crc;
  end function;

  -- Pixel packing functions

  function pack_raw8(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
  begin
    -- MSB-relative slice: pixel 0 is at pixels'left per the packing convention.
    -- Safe for over-wide actuals; equivalent to pixels(n_pixels*8-1 downto 0) when left=n_pixels*8-1.
    return pixels(pixels'left downto pixels'left - n_pixels*8 + 1);
  end function;

  function pack_raw10(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    constant n_groups : natural := n_pixels / 4;
    variable result   : std_logic_vector(n_groups*40-1 downto 0);
    variable p0, p1, p2, p3 : std_logic_vector(9 downto 0);
    variable base_px, base_out : natural;
  begin
    for g in 0 to n_groups-1 loop
      base_px  := (n_groups - g) * 4;
      p0 := pixels(base_px*10-1       downto (base_px-1)*10);
      p1 := pixels((base_px-1)*10-1   downto (base_px-2)*10);
      p2 := pixels((base_px-2)*10-1   downto (base_px-3)*10);
      p3 := pixels((base_px-3)*10-1   downto (base_px-4)*10);
      base_out := (n_groups - 1 - g) * 40;
      result(base_out+39 downto base_out+32) := p0(9 downto 2);
      result(base_out+31 downto base_out+24) := p1(9 downto 2);
      result(base_out+23 downto base_out+16) := p2(9 downto 2);
      result(base_out+15 downto base_out+8)  := p3(9 downto 2);
      result(base_out+7  downto base_out)    := p3(1 downto 0) & p2(1 downto 0) &
                                                p1(1 downto 0) & p0(1 downto 0);
    end loop;
    return result;
  end function;

  function pack_raw12(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    constant n_groups : natural := n_pixels / 2;
    variable result   : std_logic_vector(n_groups*24-1 downto 0);
    variable p0, p1   : std_logic_vector(11 downto 0);
    variable base_px, base_out : natural;
  begin
    for g in 0 to n_groups-1 loop
      base_px  := (n_groups - g) * 2;
      p0 := pixels(base_px*12-1     downto (base_px-1)*12);
      p1 := pixels((base_px-1)*12-1 downto (base_px-2)*12);
      base_out := (n_groups - 1 - g) * 24;
      result(base_out+23 downto base_out+16) := p0(11 downto 4);
      result(base_out+15 downto base_out+8)  := p1(11 downto 4);
      result(base_out+7  downto base_out)    := p1(3 downto 0) & p0(3 downto 0);
    end loop;
    return result;
  end function;

  function pack_raw14(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    constant n_groups : natural := n_pixels / 4;
    variable result   : std_logic_vector(n_groups*56-1 downto 0);
    variable p0, p1, p2, p3 : std_logic_vector(13 downto 0);
    variable base_px, base_out : natural;
  begin
    for g in 0 to n_groups-1 loop
      base_px  := (n_groups - g) * 4;
      p0 := pixels(base_px*14-1       downto (base_px-1)*14);
      p1 := pixels((base_px-1)*14-1   downto (base_px-2)*14);
      p2 := pixels((base_px-2)*14-1   downto (base_px-3)*14);
      p3 := pixels((base_px-3)*14-1   downto (base_px-4)*14);
      base_out := (n_groups - 1 - g) * 56;
      result(base_out+55 downto base_out+48) := p0(13 downto 6);
      result(base_out+47 downto base_out+40) := p1(13 downto 6);
      result(base_out+39 downto base_out+32) := p2(13 downto 6);
      result(base_out+31 downto base_out+24) := p3(13 downto 6);
      result(base_out+23 downto base_out+16) := p0(5 downto 4) & p1(5 downto 4) &
                                                p2(5 downto 4) & p3(5 downto 4);
      result(base_out+15 downto base_out+8)  := p0(3 downto 0) & p1(3 downto 0);
      result(base_out+7  downto base_out)    := p2(3 downto 0) & p3(3 downto 0);
    end loop;
    return result;
  end function;

  function pack_raw16(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    variable result : std_logic_vector(n_pixels*16-1 downto 0);
    variable p      : std_logic_vector(15 downto 0);
  begin
    for i in 0 to n_pixels-1 loop
      p := pixels((n_pixels-i)*16-1 downto (n_pixels-i-1)*16);
      -- CSI-2 RAW16: low byte transmitted first within each pixel.
      -- result layout (MSB-first): [P0_lo][P0_hi][P1_lo][P1_hi]...
      result((n_pixels-i)*16-1   downto (n_pixels-i)*16-8)  := p(7 downto 0);
      result((n_pixels-i)*16-9   downto (n_pixels-i-1)*16)  := p(15 downto 8);
    end loop;
    return result;
  end function;

  function pack_yuv422_8(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
  begin
    -- MSB-relative slice: pixel 0 is at pixels'left per the packing convention.
    -- Safe for over-wide actuals; equivalent to pixels(n_pixels*16-1 downto 0) when left=n_pixels*16-1.
    return pixels(pixels'left downto pixels'left - n_pixels*16 + 1);
  end function;

  function pack_rgb888(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
  begin
    -- MSB-relative slice: pixel 0 is at pixels'left per the packing convention.
    -- Safe for over-wide actuals; equivalent to pixels(n_pixels*24-1 downto 0) when left=n_pixels*24-1.
    return pixels(pixels'left downto pixels'left - n_pixels*24 + 1);
  end function;

  -- Internal helper: drive one byte on the link-layer AXI-Stream.
  procedure drive_byte(
    signal clk    : in  std_logic;
    signal tvalid : out std_logic;
    signal tready : in  std_logic;
    signal tdata  : out std_logic_vector(7 downto 0);
    signal tuser  : out std_logic;
    signal tlast  : out std_logic;
    constant val  : in  std_logic_vector(7 downto 0);
    constant kc   : in  std_logic;
    constant last : in  boolean
  ) is
  begin
    tdata  <= val;
    tuser  <= kc;
    tlast  <= '1' when last else '0';
    tvalid <= '1';
    wait until rising_edge(clk) and tready = '1';
    tvalid <= '0';
    tdata  <= (others => '0');
    tuser  <= '0';
    tlast  <= '0';
  end procedure;

  -- Procedure implementations (Tasks 5-6)

  procedure csi2_write_short(
    signal   clk        : in  std_logic;
    signal   tvalid     : out std_logic;
    signal   tready     : in  std_logic;
    signal   tdata      : out std_logic_vector(7 downto 0);
    signal   tuser      : out std_logic;
    signal   tlast      : out std_logic;
    constant data_type  : in  std_logic_vector(5 downto 0);
    constant vc         : in  natural range 0 to 3;
    constant word_count : in  natural
  ) is
  variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
  variable wc : std_logic_vector(15 downto 0);
begin
  wc := std_logic_vector(to_unsigned(word_count, 16));
  b0 := std_logic_vector(to_unsigned(vc, 2)) & data_type;
  b1 := wc(7 downto 0);
  b2 := wc(15 downto 8);
  b3 := csi2_ecc(b0, b1, b2);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, K_SOP, '1', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b0,   '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b1,   '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b2,   '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b3,   '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, K_EOP,'1', true);
  print(DEBUG, "csi2_write_short: DT=" & to_hstring(data_type) &
               " VC=" & integer'image(vc) & " WC=" & integer'image(word_count));
  end procedure;

  procedure csi2_write_long(
    signal   clk       : in  std_logic;
    signal   tvalid    : out std_logic;
    signal   tready    : in  std_logic;
    signal   tdata     : out std_logic_vector(7 downto 0);
    signal   tuser     : out std_logic;
    signal   tlast     : out std_logic;
    constant data_type : in  std_logic_vector(5 downto 0);
    constant vc        : in  natural range 0 to 3;
    constant payload   : in  std_logic_vector
  ) is
  variable n_bytes : natural;
  variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
  variable wc  : std_logic_vector(15 downto 0);
  variable crc : std_logic_vector(15 downto 0);
  variable byt : std_logic_vector(7 downto 0);
begin
  n_bytes := payload'length / 8;
  wc  := std_logic_vector(to_unsigned(n_bytes, 16));
  b0  := std_logic_vector(to_unsigned(vc, 2)) & data_type;
  b1  := wc(7 downto 0);
  b2  := wc(15 downto 8);
  b3  := csi2_ecc(b0, b1, b2);
  crc := csi2_crc16(payload);
  -- K_SOP
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, K_SOP, '1', false);
  -- Header (4 bytes)
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b0, '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b1, '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b2, '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, b3, '0', false);
  -- Payload bytes (MSB of payload at index 0)
  for i in 0 to n_bytes-1 loop
    byt := payload(payload'left - i*8 downto payload'left - i*8 - 7);
    drive_byte(clk, tvalid, tready, tdata, tuser, tlast, byt, '0', false);
  end loop;
  -- CRC-16 footer (2 bytes, LSB first)
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, crc(7 downto 0),  '0', false);
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, crc(15 downto 8), '0', false);
  -- K_EOP
  drive_byte(clk, tvalid, tready, tdata, tuser, tlast, K_EOP, '1', true);
  print(DEBUG, "csi2_write_long: DT=" & to_hstring(data_type) &
               " VC=" & integer'image(vc) & " bytes=" & integer'image(n_bytes));
  end procedure;

  procedure csi2_read_packet(
    signal   clk       : in  std_logic;
    signal   tvalid    : in  std_logic;
    signal   tready    : out std_logic;
    signal   tdata     : in  std_logic_vector(7 downto 0);
    signal   tuser     : in  std_logic;
    signal   tlast     : in  std_logic;
    variable data_type : out std_logic_vector(5 downto 0);
    variable vc        : out natural;
    variable payload   : out std_logic_vector;
    variable crc_ok    : out boolean
  ) is
  begin
    wait;
  end procedure;

end package body mipi_csi2_pkg;
