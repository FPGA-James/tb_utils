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

Supported signals: `tvalid`, `tready`, `tdata`, `tlast`. Optional sideband signals (`tkeep`, `tstrb`, `tid`, `tuser`) are not driven — tie them off or manage separately.

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
    constant filename : in  string
);
```

Reads a stimulus file and replays each line as one beat. File format (one beat per line):

```
DEADBEEF 0
CAFEBABE 0
12345678 1
```

Each line: `<hex_data> <last_flag>` where `last_flag` is `0` (not last) or `1` (last). Blank lines and malformed lines are skipped. Each beat is logged at DEBUG level.

**Limitations**
- `tdata` width must be a multiple of 4 bits (hex parsing via `hread`).
- No error on end-of-file mid-packet; the caller is responsible for consistent `tlast` usage in the file.

**Example**

```vhdl
axis_write(clk, tvalid, tready, tdata, tlast, "stimulus/packet0.txt");
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
