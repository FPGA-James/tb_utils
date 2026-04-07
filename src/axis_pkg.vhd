library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;

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

  -- Master: drive one beat with tuser (AXI4-Stream Video / UG934).
  -- Note: defaults omitted to avoid GHDL overload ambiguity with the file-replay overload.
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

  -- Master file-replay with tuser: reads stimulus from file and drives each line as one beat.
  -- File format per line: <hex_tdata> <tuser_int> <tlast_int>
  -- tuser=1 marks start-of-frame (UG934); tlast=1 marks end-of-scan-line.
  -- Blank and malformed lines are skipped.
  procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant filename : in  string
  );

  -- Slave: capture num_beats beats to file in <hex_tdata> <tuser> <tlast> format.
  -- Asserts tready for each beat, captures on handshake, writes one line per beat.
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
    signal   clk    : in  std_logic;
    signal   tvalid : out std_logic;
    signal   tready : in  std_logic;
    signal   tdata  : out std_logic_vector;
    signal   tlast  : out std_logic;
    signal   tuser  : out std_logic;
    constant data   : in  std_logic_vector;
    constant last   : in  boolean;
    constant user   : in  std_logic
  ) is
  begin
    tdata  <= data;
    tlast  <= '1' when last else '0';
    tuser  <= user;
    tvalid <= '1';
    wait until rising_edge(clk) and tready = '1';
    tvalid <= '0';
    tdata  <= (tdata'range => '0');
    tlast  <= '0';
    tuser  <= '0';
  end procedure;

  procedure axis_write(
    signal   clk      : in  std_logic;
    signal   tvalid   : out std_logic;
    signal   tready   : in  std_logic;
    signal   tdata    : out std_logic_vector;
    signal   tlast    : out std_logic;
    signal   tuser    : out std_logic;
    constant filename : in  string
  ) is
    file     f        : text;
    variable fstatus  : file_open_status;
    variable l        : line;
    variable v        : std_logic_vector(tdata'range);
    variable user_int : integer;
    variable last_int : integer;
    variable good     : boolean;
    variable user_sl  : std_logic;
  begin
    file_open(fstatus, f, filename, read_mode);
    assert fstatus = open_ok
      report "axis_write: cannot open file " & filename severity failure;
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0;
      hread(l, v, good);
      next when not good;
      read(l, user_int, good);
      next when not good;
      read(l, last_int, good);
      next when not good;
      user_sl := '1' when user_int /= 0 else '0';
      print(INFO, "axis_write: " & to_hstring(v) &
            " tuser=" & integer'image(user_int) &
            " tlast=" & integer'image(last_int));
      axis_write(clk, tvalid, tready, tdata, tlast, tuser,
                 v, last_int /= 0, user_sl);
    end loop;
    file_close(f);
  end procedure;

  procedure axis_read_to_file(
    signal   clk       : in  std_logic;
    signal   tvalid    : in  std_logic;
    signal   tready    : out std_logic;
    signal   tdata     : in  std_logic_vector;
    signal   tlast     : in  std_logic;
    signal   tuser     : in  std_logic;
    constant filename  : in  string;
    constant num_beats : in  positive
  ) is
    file     f : text;
    variable fstatus : file_open_status;
    variable l : line;
  begin
    file_open(fstatus, f, filename, write_mode);
    assert fstatus = open_ok
      report "axis_read_to_file: cannot open file " & filename severity failure;
    for i in 1 to num_beats loop
      tready <= '1';
      wait until rising_edge(clk) and tvalid = '1';
      tready <= '0';
      hwrite(l, tdata);
      write(l, ' ');
      if tuser = '1' then write(l, 1); else write(l, 0); end if;
      write(l, ' ');
      if tlast = '1' then write(l, 1); else write(l, 0); end if;
      writeline(f, l);
    end loop;
    file_close(f);
    print(INFO, "axis_read_to_file: captured " & integer'image(num_beats) &
          " beats to " & filename);
  end procedure;

end package body axis_pkg;
