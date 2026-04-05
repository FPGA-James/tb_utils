library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;
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

  -- Replay beats from a text file. Each line: "<hex_tdata> <0|1>"
  -- where 1 means tlast. Blank and malformed lines are skipped.
  -- Prints each beat before driving it.
  procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    constant filename : in  string
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

  procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    constant filename : in  string
  ) is
    file     f        : text;
    variable l        : line;
    variable v        : std_logic_vector(tdata'length-1 downto 0);
    variable last_int : integer;
    variable good     : boolean;
    variable fstatus  : file_open_status;
  begin
    file_open(fstatus, f, filename, read_mode);
    if fstatus /= open_ok then
      print(FATAL, "[axis.axis_write] cannot open file: " & filename);
      return;
    end if;
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0;
      hread(l, v, good);
      next when not good;
      read(l, last_int);
      print(INFO, "[axis.axis_write] data=" & to_hstring(v) &
                  " last=" & integer'image(last_int));
      axis_write(clk, tvalid, tready, tdata, tlast, v, last_int = 1);
    end loop;
    file_close(f);
  end procedure;

end package body axis_pkg;
