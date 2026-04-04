library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_pkg.all;

package axis_pkg is

  -- Master: drive one beat. Asserts tvalid, waits for tready, advances clock.
  -- Sets tlast='1' when last=true (default).
  procedure axis_write(
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean := true
  );

  -- Slave: accept one beat. Asserts tready, waits for tvalid, captures data.
  procedure axis_read(
    signal   clk    : in  std_logic;
    signal   tvalid : in  std_logic;
    signal   tready : out std_logic;
    signal   tdata  : in  std_logic_vector;
    signal   tlast  : in  std_logic;
    variable data   : out std_logic_vector;
    variable last   : out boolean
  );

  -- Passive monitor: waits for a valid beat without asserting tready.
  -- Used to snoop traffic non-intrusively.
  procedure axis_monitor(
    signal   clk    : in  std_logic;
    signal   tvalid : in  std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : in  std_logic_vector;
    signal   tlast  : in  std_logic;
    variable data   : out std_logic_vector;
    variable last   : out boolean
  );

end package axis_pkg;

package body axis_pkg is

  procedure axis_write(
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean := true
  ) is
  begin
    tdata  <= data;
    tlast  <= '1' when last else '0';
    tvalid <= '1';
    wait until rising_edge(clk) and tready = '1';
    tvalid <= '0';
    tdata  <= (tdata'range => '0');
    tlast  <= '0';
  end procedure;

  procedure axis_read(
    signal   clk    : in  std_logic;
    signal   tvalid : in  std_logic;
    signal   tready : out std_logic;
    signal   tdata  : in  std_logic_vector;
    signal   tlast  : in  std_logic;
    variable data   : out std_logic_vector;
    variable last   : out boolean
  ) is
  begin
    tready <= '1';
    wait until rising_edge(clk) and tvalid = '1';
    data   := tdata;
    last   := (tlast = '1');
    tready <= '0';
  end procedure;

  procedure axis_monitor(
    signal   clk    : in  std_logic;
    signal   tvalid : in  std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : in  std_logic_vector;
    signal   tlast  : in  std_logic;
    variable data   : out std_logic_vector;
    variable last   : out boolean
  ) is
  begin
    wait until rising_edge(clk) and tvalid = '1' and tready = '1';
    data := tdata;
    last := (tlast = '1');
  end procedure;

end package body axis_pkg;
