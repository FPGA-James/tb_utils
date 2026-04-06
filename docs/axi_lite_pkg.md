# axi_lite_pkg

AXI-Lite bus-functional models (BFMs): master write, master read, passive monitor, and file-replay variants. Address and data widths are unconstrained — inferred from the signals at the call site.

---

## Overview

| Item | Description |
|------|-------------|
| Library | `tb_utils` |
| File | `src/axi_lite_pkg.vhd` |
| Depends on | `tb_utils_pkg` |
| VHDL standard | 2008 |

AXI-Lite channels modelled: write address (AW), write data (W), write response (B), read address (AR), read data (R). All five channels are driven/monitored correctly. `BRESP` and `RRESP` are checked — a non-OKAY response logs an `[error]`.

---

## Procedures

### `axi_lite_write` — single transaction

```vhdl
procedure axi_lite_write(
    signal   clk     : in  std_logic;
    signal   awvalid : out std_logic;
    signal   awready : in  std_logic;
    signal   awaddr  : out std_logic_vector;
    signal   wvalid  : out std_logic;
    signal   wready  : in  std_logic;
    signal   wdata   : out std_logic_vector;
    signal   wstrb   : out std_logic_vector;
    signal   bvalid  : in  std_logic;
    signal   bready  : out std_logic;
    signal   bresp   : in  std_logic_vector(1 downto 0);
    constant addr    : in  std_logic_vector;
    constant data    : in  std_logic_vector
);
```

Drives AW and W simultaneously (legal per AXI-Lite spec), waits for each channel to be accepted (possibly in different cycles), then accepts the B response. All byte strobes (`wstrb`) are set to `'1'`.

**Limitations**
- `wstrb` is always all-ones; partial-byte writes are not supported.
- AW and W are driven simultaneously — slaves that require AW before W may not work correctly.
- Does not support outstanding transactions; each call blocks until the B response is received.

**Example**

```vhdl
axi_lite_write(clk,
    awvalid, awready, awaddr,
    wvalid,  wready,  wdata, wstrb,
    bvalid,  bready,  bresp,
    x"00", x"DEADBEEF");
```

---

### `axi_lite_write` — file replay

```vhdl
procedure axi_lite_write(
    signal   clk      : in  std_logic;
    -- (all AW/W/B signals) ...
    constant filename : in  string
);
```

Reads a file and issues one write transaction per line. File format:

```
00 DEADBEEF
04 CAFEBABE
08 12345678
```

Each line: `<hex_addr> <hex_data>`. Blank lines and malformed lines are skipped. Each transaction is logged at DEBUG level.

**Example**

```vhdl
axi_lite_write(clk,
    awvalid, awready, awaddr,
    wvalid,  wready,  wdata, wstrb,
    bvalid,  bready,  bresp,
    "stimulus/reg_init.txt");
```

---

### `axi_lite_read` — single transaction

```vhdl
procedure axi_lite_read(
    signal   clk     : in  std_logic;
    signal   arvalid : out std_logic;
    signal   arready : in  std_logic;
    signal   araddr  : out std_logic_vector;
    signal   rvalid  : in  std_logic;
    signal   rready  : out std_logic;
    signal   rdata   : in  std_logic_vector;
    signal   rresp   : in  std_logic_vector(1 downto 0);
    constant addr    : in  std_logic_vector;
    variable data    : out std_logic_vector
);
```

Drives the AR channel, waits for the handshake, then accepts the R response. Captured data is returned in `data`.

**Limitations**
- Does not support outstanding read transactions.
- `RRESP` is logged as an error if non-OKAY but the call still returns.

**Example**

```vhdl
variable rd : std_logic_vector(31 downto 0);

axi_lite_read(clk,
    arvalid, arready, araddr,
    rvalid,  rready,  rdata, rresp,
    x"00", rd);

check_equal(rd, x"DEADBEEF", "reg 0 read-back");
```

---

### `axi_lite_read` — file replay

```vhdl
procedure axi_lite_read(
    signal   clk      : in  std_logic;
    -- (all AR/R signals) ...
    constant filename : in  string
);
```

Issues one read per line in the file. File format — one hex address per line:

```
00
04
08
```

Each read result is printed at INFO level. Useful for quick register dump scripts.

**Example**

```vhdl
axi_lite_read(clk,
    arvalid, arready, araddr,
    rvalid,  rready,  rdata, rresp,
    "stimulus/read_addrs.txt");
```

---

### `axi_lite_monitor`

```vhdl
procedure axi_lite_monitor(
    signal   clk      : in  std_logic;
    signal   awvalid  : in  std_logic;
    signal   awready  : in  std_logic;
    signal   awaddr   : in  std_logic_vector;
    signal   wvalid   : in  std_logic;
    signal   wready   : in  std_logic;
    signal   wdata    : in  std_logic_vector;
    signal   arvalid  : in  std_logic;
    signal   arready  : in  std_logic;
    signal   araddr   : in  std_logic_vector;
    signal   rvalid   : in  std_logic;
    signal   rready   : in  std_logic;
    signal   rdata    : in  std_logic_vector;
    variable is_write : out boolean;
    variable addr_out : out std_logic_vector;
    variable data_out : out std_logic_vector
);
```

Passive monitor. Waits for the first completed handshake on either AW (write) or AR (read), captures the address and data (write data from W channel, read data from R channel), and sets `is_write` accordingly.

**Limitations**
- One call captures one complete transaction (write or read). Wrap in a loop for continuous monitoring.
- If AW and AR both become valid in the same cycle, the write takes priority.
- Does not capture `BRESP` or `RRESP`.

**Example**

```vhdl
variable txn_write : boolean;
variable txn_addr  : std_logic_vector(7 downto 0);
variable txn_data  : std_logic_vector(31 downto 0);

loop
    axi_lite_monitor(clk,
        awvalid, awready, awaddr,
        wvalid,  wready,  wdata,
        arvalid, arready, araddr,
        rvalid,  rready,  rdata,
        txn_write, txn_addr, txn_data);

    if txn_write then
        print(INFO, "WRITE addr=" & to_hstring(txn_addr)
                    & " data=" & to_hstring(txn_data));
    else
        print(INFO, "READ  addr=" & to_hstring(txn_addr)
                    & " data=" & to_hstring(txn_data));
    end if;
end loop;
```
