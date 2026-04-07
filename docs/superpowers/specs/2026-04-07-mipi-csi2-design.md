# MIPI CSI-2 Package Design

**Date:** 2026-04-07
**Scope:** Two new VHDL-2008 packages for `tb_utils` — `mipi_csi2_pkg` and `mipi_frame_pkg`

---

## 1. Goals

Provide reusable testbench BFMs for MIPI CSI-2 at the packet/frame abstraction level (no D-PHY simulation). The design supports:

- Driving a **decoded pixel AXI-Stream** (Xilinx UG934 format) into a downstream image pipeline DUT.
- Driving a **K-char framed CSI-2 byte stream** into a CSI-2 decoder or TX DUT.
- **Checking** the CSI-2 byte stream output of a TX DUT against expected packets derived from the same pixel source.

Primary use case: thermal monochrome cameras (RAW14/RAW16), but full data type coverage is included.

---

## 2. Architecture

```
tb_utils_pkg
    └── mipi_csi2_pkg   (byte/packet layer)
            └── mipi_frame_pkg  (frame/BFM layer)
```

Compilation order appended after existing packages:
1. `mipi_csi2_pkg`
2. `mipi_frame_pkg`

---

## 3. `mipi_csi2_pkg`

### 3.1 Data Type Constants

Standard CSI-2 6-bit data type codes (short packets):

| Constant         | Value (binary) | Meaning        |
|------------------|----------------|----------------|
| `DT_FRAME_START` | `000000`       | Frame Start    |
| `DT_FRAME_END`   | `000001`       | Frame End      |
| `DT_LINE_START`  | `000010`       | Line Start     |
| `DT_LINE_END`    | `000011`       | Line End       |

Long packet data types:

| Constant      | Value (binary) | Pixel format       |
|---------------|----------------|--------------------|
| `DT_RAW8`     | `101010`       | 8-bit raw          |
| `DT_RAW10`    | `101011`       | 10-bit raw         |
| `DT_RAW12`    | `101100`       | 12-bit raw         |
| `DT_RAW14`    | `101101`       | 14-bit raw         |
| `DT_RAW16`    | `101110`       | 16-bit raw         |
| `DT_YUV422_8` | `011110`       | YUV 4:2:2 8-bit    |
| `DT_RGB888`   | `100100`       | RGB 8:8:8          |

### 3.2 Link-Layer AXI-Stream Interface

The byte-stream interface carries 8b/10b decoded bytes with a K-char sideband:

| Signal   | Direction | Width | Description                              |
|----------|-----------|-------|------------------------------------------|
| `clk`    | in        | 1     | Clock                                    |
| `tvalid` | out/in    | 1     | AXI-Stream valid                         |
| `tready` | in/out    | 1     | AXI-Stream ready                         |
| `tdata`  | out/in    | 8     | Decoded byte value                       |
| `tuser`  | out/in    | 1     | `'1'` = K-character, `'0'` = data byte   |
| `tlast`  | out/in    | 1     | Asserted on K_EOP byte (last of packet)  |

### 3.3 K-Character Framing

Each CSI-2 packet is wrapped in K-chars on the link-layer stream:

```
[K27.7, tuser=1] [packet bytes, tuser=0] [K29.7, tuser=1, tlast=1]
```

| Symbol | Value | Role               |
|--------|-------|--------------------|
| K27.7  | 0xFB  | Start-of-Packet    |
| K29.7  | 0xFD  | End-of-Packet      |
| K28.5  | 0xBC  | Idle (between pkts)|

Minimum inter-packet idle K-chars: none required initially; configurable parameter reserved for future addition.

### 3.4 Procedures

```vhdl
-- Drive one K-char framed CSI-2 short packet (K_SOP + 4-byte header+ECC + K_EOP).
procedure csi2_write_short(
  signal   clk        : in  std_logic;
  signal   tvalid     : out std_logic;
  signal   tready     : in  std_logic;
  signal   tdata      : out std_logic_vector(7 downto 0);
  signal   tuser      : out std_logic;
  signal   tlast      : out std_logic;
  constant data_type  : in  std_logic_vector(5 downto 0);
  constant vc         : in  natural range 0 to 3;
  constant word_count : in  natural  -- frame/line number for FS/FE/LS/LE
);

-- Drive one K-char framed CSI-2 long packet (K_SOP + header+ECC + payload + CRC + K_EOP).
-- payload is already packed pixel bytes for one line.
procedure csi2_write_long(
  signal   clk       : in  std_logic;
  signal   tvalid    : out std_logic;
  signal   tready    : in  std_logic;
  signal   tdata     : out std_logic_vector(7 downto 0);
  signal   tuser     : out std_logic;
  signal   tlast     : out std_logic;
  constant data_type : in  std_logic_vector(5 downto 0);
  constant vc        : in  natural range 0 to 3;
  constant payload   : in  std_logic_vector  -- packed bytes, unconstrained
);

-- Monitor one K-char framed packet. Skips K28.5 idles. Syncs on K27.7 SOP.
-- Returns data_type, vc, payload bytes, and CRC check result.
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
```

### 3.5 Subprograms

**Internal (package body only):**
- `csi2_ecc(b0, b1, b2)` — 8-bit Hamming ECC over 24-bit header
- `csi2_crc16(data)` — CRC-16/CCITT over payload bytes

**Exposed (package declaration) — used by `mipi_frame_pkg`:**
- `pack_raw8 / pack_raw10 / pack_raw12 / pack_raw14 / pack_raw16 / pack_yuv422_8 / pack_rgb888` — pixel array → packed CSI-2 `std_logic_vector` (one line's worth of bytes)

`mipi_frame_pkg` calls the appropriate `pack_*` function based on `cfg.data_type`, then passes the result as `payload` to `csi2_write_long`.

---

## 4. `mipi_frame_pkg`

### 4.1 Types

```vhdl
type mipi_data_type_t is (
  RAW8, RAW10, RAW12, RAW14, RAW16, YUV422_8, RGB888
);

type mipi_frame_cfg_t is record
  width        : positive;              -- pixels per line
  height       : positive;              -- lines per frame
  data_type    : mipi_data_type_t;
  vc           : natural range 0 to 3;
  frame_number : natural range 0 to 65535;
end record;
```

### 4.2 Pixel AXI-Stream Interface (UG934)

| Signal   | Width        | Description                                    |
|----------|--------------|------------------------------------------------|
| `tdata`  | 32 or 64-bit | Pixel-packed beats; width inferred from signal |
| `tkeep`  | tdata/8      | Byte enable; marks valid bytes in last beat    |
| `tlast`  | 1            | End-of-line                                    |
| `tuser`  | 1            | Start-of-frame (first beat of frame only)      |

Pixels per beat by data type:

| data_type | Bits/pixel (padded) | 32-bit bus | 64-bit bus |
|-----------|---------------------|------------|------------|
| RAW8      | 8                   | 4 px/beat  | 8 px/beat  |
| RAW10     | 16 (UG934 pad)      | 2 px/beat  | 4 px/beat  |
| RAW12     | 16 (UG934 pad)      | 2 px/beat  | 4 px/beat  |
| RAW14     | 16 (UG934 pad)      | 2 px/beat  | 4 px/beat  |
| RAW16     | 16                  | 2 px/beat  | 4 px/beat  |
| YUV422_8  | 16                  | 2 px/beat  | 4 px/beat  |
| RGB888    | 32 (pad 8)          | 1 px/beat  | 2 px/beat  |

`tuser` is asserted on the first beat of the frame. `tlast` is asserted on the last beat of each line. `tkeep` marks valid bytes in the last beat of a line when the line width is not a multiple of pixels-per-beat.

### 4.3 Procedures

```vhdl
-- Drive decoded UG934 pixel AXI-Stream. tuser=1 on first beat of frame.
-- tlast=1 on last beat of each line. tdata width inferred from signal.
-- Pixel file: one hex pixel value per line; blank lines and # comments skipped.
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
--   FS short packet, one long packet per line, FE short packet.
-- Reads same pixel file as mipi_frame_write; packs pixels per CSI-2 spec.
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
-- Independently computes expected packets from cfg + filename.
-- Reports mismatches via tb_utils_pkg print(ERROR, ...).
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
```

---

## 5. Pixel File Format

Plain text, one pixel per line as an unsigned hex value. Leading zeros to fill the pixel bit width. Blank lines and lines beginning with `#` are skipped.

| data_type | Bits | Hex chars per line | Example  |
|-----------|------|--------------------|----------|
| RAW8      | 8    | 2                  | `FF`     |
| RAW10     | 10   | 3                  | `3FF`    |
| RAW12     | 12   | 3                  | `FFF`    |
| RAW14     | 14   | 4                  | `3FFF`   |
| RAW16     | 16   | 4                  | `FFFF`   |
| YUV422_8  | 16   | 4                  | `80EB`   |
| RGB888    | 24   | 6                  | `FF8000` |

Total pixels in file: `cfg.width * cfg.height`.

---

## 6. Testbench Structure

Self-test: `tb/mipi_tb.vhd` — loopbacks `mipi_packet_write` directly into `mipi_packet_check` with no DUT. Runs multiple frames sweeping all data types and all four VCs. Generates a synthetic ramp pixel file before each frame. Uses `tb_scoreboard_pkg` and `coverage_pkg`.

### 6.1 Scoreboard Usage

A `scoreboard_t` is used at the testbench level — BFM procedures remain scoreboard-unaware. The self-test TB uses the **lower-level** `csi2_write_short` / `csi2_write_long` / `csi2_read_packet` procedures directly in loops (the same pattern as `axis_tb.vhd` with `axis_write` / `axis_read`):

- **Writer process:** for each line — pack pixels, push packed bytes onto scoreboard, call `csi2_write_long`.
- **Checker process:** call `csi2_read_packet` per packet; for each received long packet, pop expected bytes from scoreboard and compare.

The high-level `mipi_packet_write` / `mipi_packet_check` procedures are used in DUT testbenches where scoreboard integration is not needed at line granularity.

### 6.2 Coverage

Four coverage groups:

| Group           | Bins                                               | Purpose                                      |
|-----------------|----------------------------------------------------|----------------------------------------------|
| `data_type_cov` | One bin per data type (7 bins)                     | All pixel formats exercised                  |
| `vc_cov`        | One bin per VC: 0, 1, 2, 3                         | All virtual channels exercised               |
| `pixel_val_cov` | Value range bins over pixel bit width (8 bins)     | Pixel value space covered (ramp + random)    |
| `frame_dim_cov` | Bins for small / medium / large frame widths       | Different line lengths exercised             |

Simulation runs until all coverage groups are fully covered or a timeout is reached, consistent with the pattern in `axis_tb.vhd`.

### 6.3 Typical DUT Testbench Pattern

```vhdl
-- Same cfg and pixel file drives both processes
pixel_master : process begin
  mipi_frame_write(clk, px_valid, px_ready, px_data, px_keep,
                   px_last, px_user, CFG, "frame.hex");
  wait;
end process;

packet_checker : process
  variable pass : boolean;
begin
  mipi_packet_check(clk, dut_valid, dut_ready, dut_data,
                    dut_kchar, dut_last, CFG, "frame.hex", pass);
  assert pass report "CSI-2 packet mismatch" severity failure;
  wait;
end process;
```

---

## 7. Out of Scope

- D-PHY / C-PHY physical layer simulation
- Minimum inter-packet idle K-char count (reserved for future parameter)
- Multi-frame sequences (call procedures multiple times with incrementing `frame_number`)
- Virtual channel demultiplexing on the checker side (single VC per checker instance)
- CSI-2 v2 extended VC (VC 4–15)
