# axis_pkg

AXI-Stream bus-functional models (BFMs): master writer, slave reader, passive monitor, and file-replay variants. Bus width is unconstrained — inferred from the signals at the call site.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/axis_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

Supported signals: `tvalid`, `tready`, `tdata`, `tlast`, `tuser`. Other optional sideband signals (`tkeep`, `tstrb`, `tid`) are not driven — tie them off or manage separately.

---

## Procedures

### `axis_write` — single beat

```vhdl
procedure axis_write(
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean := true
);
```

Master BFM. Drives `tdata`, `tlast`, and `tvalid`, then waits for a rising clock edge where `tready = '1'` (handshake). Deasserts `tvalid` and zeroes `tdata`/`tlast` after the handshake.

**Limitations**
- Drives aw+w channels simultaneously; does not model back-pressure delays — `tvalid` is held until the slave accepts.
- `data` width must match the `tdata` signal width.

**Example**

```vhdl
-- Single beat, marked as last
axis_write(clk, tvalid, tready, tdata, tlast, x"DEADBEEF");

-- Burst: first two beats not last, final beat is last
axis_write(clk, tvalid, tready, tdata, tlast, x"AABB", last => false);
axis_write(clk, tvalid, tready, tdata, tlast, x"CCDD", last => false);
axis_write(clk, tvalid, tready, tdata, tlast, x"EEFF", last => true);
```

---

### `axis_write` — file replay

```vhdl
procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant filename : in  string
);
```

Reads a stimulus file and replays each line as one beat. File format (one beat per line):

```
DEADBEEF 0 0
CAFEBABE 0 0
12345678 0 1
```

Each line: `<hex_tdata> <tuser> <tlast>`. `tuser = 1` marks start-of-frame (AXI4-Stream Video). Blank lines and malformed lines are skipped. Each beat is logged at INFO level before driving.

**Limitations**
- `tdata` width must be a multiple of 4 bits (hex parsing via `hread`).
- No error on end-of-file mid-packet; the caller is responsible for consistent `tlast` usage in the file.

**Example**

```vhdl
axis_write(clk, tvalid, tready, tdata, tlast, tuser, "stimulus/frame0.txt");
```

---

### `axis_read`

```vhdl
procedure axis_read(
    signal   clk    : in  std_logic;
    signal   tvalid : in  std_logic;
    signal   tready : out std_logic;
    signal   tdata  : in  std_logic_vector;
    signal   tlast  : in  std_logic;
    variable data   : out std_logic_vector;
    variable last   : out boolean
);
```

Slave BFM. Asserts `tready`, waits for a rising edge where `tvalid = '1'`, then captures `tdata` and `tlast` into the output variables. Deasserts `tready` after the handshake.

**Limitations**
- `tready` is held high for exactly one accepted beat. If the master drives multi-beat bursts continuously, call `axis_read` in a loop.
- The slave asserts `tready` immediately — there is no configurable latency before acceptance.

**Example**

```vhdl
variable rx_data : std_logic_vector(31 downto 0);
variable rx_last : boolean;

axis_read(clk, tvalid, tready, tdata, tlast, rx_data, rx_last);
sb.check(rx_data, "beat 0");
```

---

### `axis_monitor`

```vhdl
procedure axis_monitor(
    signal   clk    : in  std_logic;
    signal   tvalid : in  std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : in  std_logic_vector;
    signal   tlast  : in  std_logic;
    variable data   : out std_logic_vector;
    variable last   : out boolean
);
```

Passive monitor — observes traffic without driving any signals. Waits for a rising edge where both `tvalid = '1'` and `tready = '1'` (completed handshake), then captures the beat.

**Limitations**
- Purely passive; must not be the only consumer of valid beats (the slave must also drive `tready`).
- One call captures one beat; wrap in a loop for continuous monitoring.

**Example**

```vhdl
-- In a separate monitoring process
loop
    axis_monitor(clk, tvalid, tready, tdata, tlast, mon_data, mon_last);
    print(DEBUG, "monitor saw: 0x" & to_hstring(mon_data));
end loop;
```

---

## TUSER variants (video / UG934 format)

The following overloads extend the write/read procedures with a `tuser` signal for AXI4-Stream Video (UG934). `tuser = '1'` marks the first beat of a frame (start-of-frame). File format is `<hex_tdata> <tuser> <tlast>` per line.

### `axis_write` — single beat with TUSER

```vhdl
procedure axis_write(
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    signal   tuser  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean;
    constant user   : in  std_logic
);
```

Same handshake as the non-TUSER variant. `last` and `user` have no defaults — supply both explicitly.

> **Note:** Defaults are omitted to avoid GHDL overload ambiguity with the file-replay overload below.

**Example**

```vhdl
-- Start-of-frame beat
axis_write(clk, tvalid, tready, tdata, tlast, tuser, x"FF0000", false, '1');
-- Mid-frame beat
axis_write(clk, tvalid, tready, tdata, tlast, tuser, x"00FF00", false, '0');
```

---

### `axis_write` — file replay with TUSER

```vhdl
procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant filename : in  string
);
```

Reads a stimulus file and drives one beat per line. File format (one beat per line):

```
FF0000 1 0
00FF00 0 0
0000FF 0 0
A1B2C3 0 1
```

Each line: `<hex_tdata> <tuser> <tlast>`. Blank and malformed lines are skipped. Each beat is logged at INFO level before driving.

**Example**

```vhdl
axis_write(clk, tvalid, tready, tdata, tlast, tuser, "tb/frame_in.txt");
```

---

### `axis_read_to_file`

```vhdl
procedure axis_read_to_file(
    signal   clk       : in  std_logic;
    signal   tvalid    : in  std_logic;
    signal   tready    : out std_logic;
    signal   tdata     : in  std_logic_vector;
    signal   tlast     : in  std_logic;
    signal   tuser     : in  std_logic;
    constant filename  : in  string;
    constant num_beats : in  positive
);
```

Slave BFM. Captures exactly `num_beats` beats from the bus and writes each to `filename` in `<hex_tdata> <tuser> <tlast>` format. The caller determines `num_beats` from the image dimensions (e.g. `width * height`). Logs a summary at INFO level after capturing.

**File extension:** `.txt`, `.hex`, and `.mem` are all valid.

**Limitations**
- `tready` pulses low briefly between beats (one delta cycle). For pipelined sources that present the next beat without a gap, this causes back-pressure on every beat. Suitable for frame-accurate but not throughput-critical capture.

**Example**

```vhdl
-- Capture a 1920x1080 frame
axis_read_to_file(clk, tvalid, tready, tdata, tlast, tuser,
                  "work/frame_out.txt", 1920*1080);

-- Compare with golden reference
file_compare("tb/frame_in.txt", "work/frame_out.txt");
```
