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

  -- Pixel packing stubs (real implementations in Task 4)

  function pack_raw8(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
  begin
    return pixels(n_pixels*8-1 downto 0);
  end function;

  function pack_raw10(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    constant n_groups : natural := n_pixels / 4;
    variable result   : std_logic_vector(n_groups*40-1 downto 0) := (others => '0');
  begin
    return result;
  end function;

  function pack_raw12(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    constant n_groups : natural := n_pixels / 2;
    variable result   : std_logic_vector(n_groups*24-1 downto 0) := (others => '0');
  begin
    return result;
  end function;

  function pack_raw14(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    constant n_groups : natural := n_pixels / 4;
    variable result   : std_logic_vector(n_groups*56-1 downto 0) := (others => '0');
  begin
    return result;
  end function;

  function pack_raw16(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    variable result : std_logic_vector(n_pixels*16-1 downto 0) := (others => '0');
  begin
    return result;
  end function;

  function pack_yuv422_8(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    variable result : std_logic_vector(n_pixels*16-1 downto 0) := (others => '0');
  begin
    return result;
  end function;

  function pack_rgb888(pixels : std_logic_vector; n_pixels : positive)
    return std_logic_vector is
    variable result : std_logic_vector(n_pixels*24-1 downto 0) := (others => '0');
  begin
    return result;
  end function;

  -- Procedure stubs (real implementations in Tasks 5-6)

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
  begin
    null;
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
  begin
    null;
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
