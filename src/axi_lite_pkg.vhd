library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_pkg.all;

package axi_lite_pkg is

  -- Master write: drives aw+w channels, waits for b response.
  -- wstrb width must equal wdata'length/8.
  procedure axi_lite_write(
    signal   clk     : in  std_logic;
    -- Write address channel
    signal   awvalid : out std_logic;
    signal   awready : in  std_logic;
    signal   awaddr  : out std_logic_vector;
    -- Write data channel
    signal   wvalid  : out std_logic;
    signal   wready  : in  std_logic;
    signal   wdata   : out std_logic_vector;
    signal   wstrb   : out std_logic_vector;
    -- Write response channel
    signal   bvalid  : in  std_logic;
    signal   bready  : out std_logic;
    signal   bresp   : in  std_logic_vector(1 downto 0);
    -- Arguments
    constant addr    : in  std_logic_vector;
    constant data    : in  std_logic_vector
  );

  -- Master read: drives ar channel, captures rdata.
  procedure axi_lite_read(
    signal   clk     : in  std_logic;
    -- Read address channel
    signal   arvalid : out std_logic;
    signal   arready : in  std_logic;
    signal   araddr  : out std_logic_vector;
    -- Read data channel
    signal   rvalid  : in  std_logic;
    signal   rready  : out std_logic;
    signal   rdata   : in  std_logic_vector;
    signal   rresp   : in  std_logic_vector(1 downto 0);
    -- Arguments
    constant addr    : in  std_logic_vector;
    variable data    : out std_logic_vector
  );

  -- Passive monitor: captures one complete write or read transaction.
  procedure axi_lite_monitor(
    signal   clk      : in  std_logic;
    -- Write address
    signal   awvalid  : in  std_logic;
    signal   awready  : in  std_logic;
    signal   awaddr   : in  std_logic_vector;
    -- Write data
    signal   wvalid   : in  std_logic;
    signal   wready   : in  std_logic;
    signal   wdata    : in  std_logic_vector;
    -- Read address
    signal   arvalid  : in  std_logic;
    signal   arready  : in  std_logic;
    signal   araddr   : in  std_logic_vector;
    -- Read data
    signal   rvalid   : in  std_logic;
    signal   rready   : in  std_logic;
    signal   rdata    : in  std_logic_vector;
    -- Outputs
    variable is_write : out boolean;
    variable addr_out : out std_logic_vector;
    variable data_out : out std_logic_vector
  );

end package axi_lite_pkg;

package body axi_lite_pkg is

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
  ) is
  begin
    -- Drive address and data simultaneously (legal in AXI-Lite)
    awaddr  <= addr;
    awvalid <= '1';
    wdata   <= data;
    wstrb   <= (wstrb'range => '1');  -- all byte lanes valid
    wvalid  <= '1';

    -- Wait for both channels to be accepted (may happen same or different cycles)
    wait until rising_edge(clk) and awready = '1';
    awvalid <= '0';
    awaddr  <= (awaddr'range => '0');

    wait until rising_edge(clk) and wready = '1';
    wvalid  <= '0';
    wdata   <= (wdata'range => '0');
    wstrb   <= (wstrb'range => '0');

    -- Accept write response
    bready <= '1';
    wait until rising_edge(clk) and bvalid = '1';
    bready <= '0';

    if bresp /= "00" then
      print(ERROR, "[axi-lite] write: bad BRESP = " & to_hstring(bresp));
    end if;
  end procedure;

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
  ) is
  begin
    araddr  <= addr;
    arvalid <= '1';
    wait until rising_edge(clk) and arready = '1';
    arvalid <= '0';
    araddr  <= (araddr'range => '0');

    rready <= '1';
    wait until rising_edge(clk) and rvalid = '1';
    data   := rdata;
    rready <= '0';

    if rresp /= "00" then
      print(ERROR, "[axi-lite] read: bad RRESP = " & to_hstring(rresp));
    end if;
  end procedure;

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
  ) is
  begin
    -- Wait for first activity on either aw or ar
    wait until rising_edge(clk) and
      ((awvalid = '1' and awready = '1') or (arvalid = '1' and arready = '1'));

    if awvalid = '1' and awready = '1' then
      is_write := true;
      addr_out := awaddr;
      -- Capture write data (may already be valid)
      if wvalid = '1' and wready = '1' then
        data_out := wdata;
      else
        wait until rising_edge(clk) and wvalid = '1' and wready = '1';
        data_out := wdata;
      end if;
    else
      is_write := false;
      addr_out := araddr;
      wait until rising_edge(clk) and rvalid = '1' and rready = '1';
      data_out := rdata;
    end if;
  end procedure;

end package body axi_lite_pkg;
