# AXI4 Phase 2 Design

**Date:** 2026-04-08
**Scope:** `axi4_pkg` (BFM procedures), `axi4_mem` (AXI4 slave RAM), `axi_lite_mem` (AXI-Lite slave RAM), and two self-test testbenches.

---

## 1. Goals

Provide:
- A full AXI4 BFM package (`axi4_pkg`) with pipelined low-level channel procedures and blocking convenience wrappers.
- A synthesisable AXI4 slave RAM entity (`axi4_mem`) whose width and depth are inferred from port connections.
- A synthesisable AXI-Lite slave RAM entity (`axi_lite_mem`) with the same inference approach.
- Self-test TBs (`axi4_tb`, `axi_lite_mem_tb`) using scoreboard and coverage.

All burst types (INCR, FIXED, WRAP), narrow transfers, and multiple IDs are supported. One outstanding write and one outstanding read may proceed simultaneously on independent channels.

---

## 2. Architecture

```
tb_utils library:
  tb_utils_pkg
      └── axi4_pkg          (uses tb_utils_pkg)

work library:
  axi4_mem                  (uses tb_utils_pkg for logging)
  axi_lite_mem              (uses tb_utils_pkg for logging)

TBs (work):
  axi4_tb                   (uses axi4_pkg, axi4_mem)
  axi_lite_mem_tb           (uses axi_lite_pkg, axi_lite_mem)
```

**New files:**

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/axi4_pkg.vhd` | AXI4 BFM channel procedures + wrappers + monitor |
| Create | `mem_model/axi4_mem.vhd` | AXI4 slave RAM entity |
| Create | `mem_model/axi_lite_mem.vhd` | AXI-Lite slave RAM entity |
| Create | `tb/axi4_tb.vhd` | AXI4 self-test TB |
| Create | `tb/axi_lite_mem_tb.vhd` | AXI-Lite memory model self-test TB |
| Modify | `Makefile` | Add new SRC, MEM_MODEL, TB entries |

**Compilation order additions** (after `axi_lite_pkg`):
1. `src/axi4_pkg.vhd` → `tb_utils` library
2. `mem_model/axi4_mem.vhd` → `work` library
3. `mem_model/axi_lite_mem.vhd` → `work` library
4. `tb/axi4_tb.vhd` → `work` library
5. `tb/axi_lite_mem_tb.vhd` → `work` library

---

## 3. `axi4_pkg`

### 3.1 Constants

```vhdl
constant AXI4_BURST_FIXED : std_logic_vector(1 downto 0) := "00";
constant AXI4_BURST_INCR  : std_logic_vector(1 downto 0) := "01";
constant AXI4_BURST_WRAP  : std_logic_vector(1 downto 0) := "10";

constant AXI4_RESP_OKAY   : std_logic_vector(1 downto 0) := "00";
constant AXI4_RESP_EXOKAY : std_logic_vector(1 downto 0) := "01";
constant AXI4_RESP_SLVERR : std_logic_vector(1 downto 0) := "10";
constant AXI4_RESP_DECERR : std_logic_vector(1 downto 0) := "11";
```

### 3.2 Low-Level Channel Procedures

Each procedure handles exactly one AXI4 channel. They can be called from independent processes for true pipeline parallelism.

```vhdl
-- Write address channel: drive AW signals, wait for AWREADY handshake.
-- len = number of beats (1–256); internally AWLEN = len-1.
-- size = bytes per beat = 2^size (0=byte, 1=halfword, etc.); defaults to full bus width.
-- burst: AXI4_BURST_INCR (default), AXI4_BURST_FIXED, AXI4_BURST_WRAP.
procedure axi4_write_addr(
  signal   clk     : in  std_logic;
  signal   awvalid : out std_logic;
  signal   awready : in  std_logic;
  signal   awaddr  : out std_logic_vector;
  signal   awlen   : out std_logic_vector(7 downto 0);
  signal   awsize  : out std_logic_vector(2 downto 0);
  signal   awburst : out std_logic_vector(1 downto 0);
  signal   awid    : out std_logic_vector;
  constant addr    : in  std_logic_vector;
  constant len     : in  positive;
  constant size    : in  natural;
  constant burst   : in  std_logic_vector(1 downto 0) := AXI4_BURST_INCR;
  constant id      : in  std_logic_vector
);

-- Write data channel: drive all len beats with WSTRB, assert WLAST on final beat.
-- data: all beats concatenated, beat 0 at MSB (data'left).
-- strb: all WSTRB values concatenated, beat 0 at MSB; defaults to all-ones (all bytes valid).
procedure axi4_write_data(
  signal   clk    : in  std_logic;
  signal   wvalid : out std_logic;
  signal   wready : in  std_logic;
  signal   wdata  : out std_logic_vector;
  signal   wstrb  : out std_logic_vector;
  signal   wlast  : out std_logic;
  constant data   : in  std_logic_vector;
  constant len    : in  positive;
  constant strb   : in  std_logic_vector          -- sized to len*(wdata'length/8); all-ones = all bytes valid
);

-- Write response channel: accept one BRESP, return response code and BID.
-- Logs ERROR if resp /= OKAY.
procedure axi4_write_resp(
  signal   clk    : in  std_logic;
  signal   bvalid : in  std_logic;
  signal   bready : out std_logic;
  signal   bresp  : in  std_logic_vector(1 downto 0);
  signal   bid    : in  std_logic_vector;
  variable resp   : out std_logic_vector(1 downto 0);
  variable id_out : out std_logic_vector
);

-- Read address channel: drive AR signals, wait for ARREADY handshake.
procedure axi4_read_addr(
  signal   clk     : in  std_logic;
  signal   arvalid : out std_logic;
  signal   arready : in  std_logic;
  signal   araddr  : out std_logic_vector;
  signal   arlen   : out std_logic_vector(7 downto 0);
  signal   arsize  : out std_logic_vector(2 downto 0);
  signal   arburst : out std_logic_vector(1 downto 0);
  signal   arid    : out std_logic_vector;
  constant addr    : in  std_logic_vector;
  constant len     : in  positive;
  constant size    : in  natural;
  constant burst   : in  std_logic_vector(1 downto 0) := AXI4_BURST_INCR;
  constant id      : in  std_logic_vector
);

-- Read data channel: accept all len beats, return concatenated data (beat 0 at MSB).
-- Logs ERROR if any rresp /= OKAY or if rlast is not asserted on final beat.
procedure axi4_read_data(
  signal   clk    : in  std_logic;
  signal   rvalid : in  std_logic;
  signal   rready : out std_logic;
  signal   rdata  : in  std_logic_vector;
  signal   rresp  : in  std_logic_vector(1 downto 0);
  signal   rlast  : in  std_logic;
  signal   rid    : in  std_logic_vector;
  variable data   : out std_logic_vector;
  variable resp   : out std_logic_vector(1 downto 0);
  variable id_out : out std_logic_vector
);
```

### 3.3 Blocking Convenience Wrappers

```vhdl
-- Blocking write: address → data → response in sequence (single process).
procedure axi4_write(
  signal   clk     : in  std_logic;
  signal   awvalid : out std_logic;
  signal   awready : in  std_logic;
  signal   awaddr  : out std_logic_vector;
  signal   awlen   : out std_logic_vector(7 downto 0);
  signal   awsize  : out std_logic_vector(2 downto 0);
  signal   awburst : out std_logic_vector(1 downto 0);
  signal   awid    : out std_logic_vector;
  signal   wvalid  : out std_logic;
  signal   wready  : in  std_logic;
  signal   wdata   : out std_logic_vector;
  signal   wstrb   : out std_logic_vector;
  signal   wlast   : out std_logic;
  signal   bvalid  : in  std_logic;
  signal   bready  : out std_logic;
  signal   bresp   : in  std_logic_vector(1 downto 0);
  signal   bid     : in  std_logic_vector;
  constant addr    : in  std_logic_vector;
  constant data    : in  std_logic_vector;
  constant id      : in  std_logic_vector;
  constant len     : in  positive;
  constant burst   : in  std_logic_vector(1 downto 0) := AXI4_BURST_INCR;
  constant size    : in  natural                       := 0  -- 0 = full bus width
);

-- Blocking read: address → data in sequence (single process).
procedure axi4_read(
  signal   clk     : in  std_logic;
  signal   arvalid : out std_logic;
  signal   arready : in  std_logic;
  signal   araddr  : out std_logic_vector;
  signal   arlen   : out std_logic_vector(7 downto 0);
  signal   arsize  : out std_logic_vector(2 downto 0);
  signal   arburst : out std_logic_vector(1 downto 0);
  signal   arid    : out std_logic_vector;
  signal   rvalid  : in  std_logic;
  signal   rready  : out std_logic;
  signal   rdata   : in  std_logic_vector;
  signal   rresp   : in  std_logic_vector(1 downto 0);
  signal   rlast   : in  std_logic;
  signal   rid     : in  std_logic_vector;
  constant addr    : in  std_logic_vector;
  constant id      : in  std_logic_vector;
  constant len     : in  positive;
  constant burst   : in  std_logic_vector(1 downto 0) := AXI4_BURST_INCR;
  constant size    : in  natural                       := 0;
  variable data    : out std_logic_vector
);
```

### 3.4 Passive Monitor

```vhdl
-- Snoops one complete write or read transaction without driving any signals.
-- Waits for AW or AR valid+ready (whichever comes first), then captures the full transaction.
procedure axi4_monitor(
  signal   clk      : in  std_logic;
  signal   awvalid  : in  std_logic;
  signal   awready  : in  std_logic;
  signal   awaddr   : in  std_logic_vector;
  signal   awlen    : in  std_logic_vector(7 downto 0);
  signal   awburst  : in  std_logic_vector(1 downto 0);
  signal   awid     : in  std_logic_vector;
  signal   wvalid   : in  std_logic;
  signal   wready   : in  std_logic;
  signal   wdata    : in  std_logic_vector;
  signal   wlast    : in  std_logic;
  signal   arvalid  : in  std_logic;
  signal   arready  : in  std_logic;
  signal   araddr   : in  std_logic_vector;
  signal   arlen    : in  std_logic_vector(7 downto 0);
  signal   arburst  : in  std_logic_vector(1 downto 0);
  signal   arid     : in  std_logic_vector;
  signal   rvalid   : in  std_logic;
  signal   rready   : in  std_logic;
  signal   rdata    : in  std_logic_vector;
  signal   rlast    : in  std_logic;
  variable is_write : out boolean;
  variable addr_out : out std_logic_vector;
  variable data_out : out std_logic_vector;
  variable id_out   : out std_logic_vector;
  variable len_out  : out natural
);
```

### 3.5 Data Conventions

- **Burst data:** All beats concatenated into a single `std_logic_vector`. Beat 0 at MSB (`data'left`). Caller sizes the vector to `len * wdata'length` bits.
- **WSTRB:** All strobe values concatenated similarly; beat 0 at MSB. If the `strb` parameter is zero-length, all byte lanes are enabled (all-ones default).
- **`len`:** Number of beats (1–256). Internally `AWLEN/ARLEN = len - 1`.
- **`size`:** Bytes per beat as `2^size`. Value 0 means full bus width (auto-computed from `wdata'length`).
- **Burst type address generation:**
  - INCR: each beat address increments by `2^size` bytes.
  - FIXED: all beats use the same address.
  - WRAP: address wraps at the boundary `len * 2^size` bytes aligned to start.

---

## 4. Memory Models

### 4.1 `axi4_mem`

```vhdl
entity axi4_mem is
  port (
    clk    : in  std_logic;
    rst_n  : in  std_logic;
    -- Write address channel
    awid    : in  std_logic_vector;
    awaddr  : in  std_logic_vector;
    awlen   : in  std_logic_vector(7 downto 0);
    awsize  : in  std_logic_vector(2 downto 0);
    awburst : in  std_logic_vector(1 downto 0);
    awvalid : in  std_logic;
    awready : out std_logic;
    -- Write data channel
    wdata   : in  std_logic_vector;
    wstrb   : in  std_logic_vector;
    wlast   : in  std_logic;
    wvalid  : in  std_logic;
    wready  : out std_logic;
    -- Write response channel
    bid     : out std_logic_vector;
    bresp   : out std_logic_vector(1 downto 0);
    bvalid  : out std_logic;
    bready  : in  std_logic;
    -- Read address channel
    arid    : in  std_logic_vector;
    araddr  : in  std_logic_vector;
    arlen   : in  std_logic_vector(7 downto 0);
    arsize  : in  std_logic_vector(2 downto 0);
    arburst : in  std_logic_vector(1 downto 0);
    arvalid : in  std_logic;
    arready : out std_logic;
    -- Read data channel
    rid     : out std_logic_vector;
    rdata   : out std_logic_vector;
    rresp   : out std_logic_vector(1 downto 0);
    rlast   : out std_logic;
    rvalid  : out std_logic;
    rready  : in  std_logic
  );
end entity axi4_mem;
```

**Internal storage:** `array(0 to 2**awaddr'length - 1) of std_logic_vector(wdata'length-1 downto 0)`, word-addressed. Byte enables applied per WSTRB lane.

**Behaviour:**
- Write and read channels operate independently and simultaneously (one outstanding write + one outstanding read at a time).
- Write path: accept AW handshake → latch AWID, address, burst params → accept W beats applying WSTRB → issue BRESP with BID = latched AWID.
- Read path: accept AR handshake → latch ARID, address, burst params → generate RDATA beats with RID = latched ARID, assert RLAST on final beat.
- All three burst types: INCR (beat address increments by 2^AWSIZE), FIXED (same address every beat), WRAP (wraps at aligned boundary).
- Narrow transfers: on writes, only WSTRB-enabled byte lanes written; on reads, unused byte lanes return zero.
- BRESP and RRESP always OKAY (0x0); no error injection in this version.
- Logs write and read transactions at DEBUG level via `tb_utils_pkg.print`.

### 4.2 `axi_lite_mem`

```vhdl
entity axi_lite_mem is
  port (
    clk    : in  std_logic;
    rst_n  : in  std_logic;
    -- Write address channel
    awaddr  : in  std_logic_vector;
    awvalid : in  std_logic;
    awready : out std_logic;
    -- Write data channel
    wdata   : in  std_logic_vector;
    wstrb   : in  std_logic_vector;
    wvalid  : in  std_logic;
    wready  : out std_logic;
    -- Write response channel
    bresp   : out std_logic_vector(1 downto 0);
    bvalid  : out std_logic;
    bready  : in  std_logic;
    -- Read address channel
    araddr  : in  std_logic_vector;
    arvalid : in  std_logic;
    arready : out std_logic;
    -- Read data channel
    rdata   : out std_logic_vector;
    rresp   : out std_logic_vector(1 downto 0);
    rvalid  : out std_logic;
    rready  : in  std_logic
  );
end entity axi_lite_mem;
```

**Internal storage:** Same inference pattern as `axi4_mem`. One outstanding write and one outstanding read simultaneously. No burst, no ID, no WLAST. WSTRB applied per byte lane. Always responds OKAY.

---

## 5. Testbenches

### 5.1 `axi4_tb`

Instantiates `axi4_mem` with a 10-bit address bus (1024 words) and 32-bit data bus. Three concurrent BFM processes:

- **Write address process:** drives `axi4_write_addr` calls
- **Write data process:** drives `axi4_write_data` calls (can overlap with address phase)
- **Control process:** calls `axi4_write_resp`, then `axi4_read_addr` + `axi4_read_data`, checks scoreboard

**Scoreboard:** Push expected write data before each burst; pop and compare on read-back.

**Coverage groups:**

| Group | Bins | Purpose |
|---|---|---|
| `burst_type_cov` | FIXED(0), INCR(1), WRAP(2) | All burst types exercised |
| `burst_len_cov` | short(1), medium(2–15), long(16–256) | Various burst lengths |
| `id_cov` | id0, id1, id2, id3 | Multiple transaction IDs |
| `size_cov` | byte(0), halfword(1), word(2), fullwidth(3) | All transfer sizes |

Loop until all coverage closed or 5 ms timeout. Final `sb.final_report` + `check_equal(sb.fail_count, 0)`.

### 5.2 `axi_lite_mem_tb`

Instantiates `axi_lite_mem` with 8-bit address (256 words) and 32-bit data. Single process using existing `axi_lite_pkg` procedures: write random data to all addresses, read back and scoreboard-check.

**Coverage:** Address range bins (low/mid/high), write+read transaction type.

---

## 6. Makefile Changes

```makefile
MEM_MODEL := \
  mem_model/axi4_mem.vhd \
  mem_model/axi_lite_mem.vhd

SRC := ... (existing) ...
  src/axi4_pkg.vhd

TBS := ... (existing) ...
  tb/axi4_tb.vhd \
  tb/axi_lite_mem_tb.vhd

TB_TOPS := ... (existing) ... axi4_tb axi_lite_mem_tb
```

The `mem_model/` files are compiled into the `work` library (not `tb_utils`), so `ghdl -a --work=work` rather than `--work=tb_utils`.

---

## 7. Out of Scope

- Multiple simultaneous outstanding write transactions (more than one AWID in-flight at once)
- Multiple simultaneous outstanding read transactions
- AXI4 exclusive access (LOCK signal)
- QoS, region, user sideband signals
- Error injection (SLVERR, DECERR responses)
- Cache, protection (ARCACHE, ARPROT etc.) — ports present but ignored by memory model
