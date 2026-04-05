-- =============================================================================
-- axi_stream_sink.vhd
-- Active AXI-Stream sink — drives TREADY, captures beats to memory and console
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.axi_stream_vip_pkg.all;

entity axi_stream_sink is
  generic (
    G_DATA_BYTES    : positive := 4;     -- Number of data bytes (bus width / 8)
    G_ID_WIDTH      : natural  := 0;     -- TID width  (0 = not present)
    G_DEST_WIDTH    : natural  := 0;     -- TDEST width (0 = not present)
    G_USER_WIDTH    : natural  := 0;     -- TUSER width (0 = not present)
    G_TREADY_ALWAYS : boolean  := true;  -- true = always ready; false = random backpressure
    G_READY_PROB    : real     := 0.8;   -- TREADY assert probability when G_TREADY_ALWAYS=false
    G_NAME          : string   := "AXIS_SINK"
  );
  port (
    aclk     : in  std_logic;
    aresetn  : in  std_logic;
    tvalid   : in  std_logic;
    tready   : out std_logic;
    tdata    : in  std_logic_vector(G_DATA_BYTES * 8 - 1 downto 0);
    tkeep    : in  std_logic_vector(G_DATA_BYTES - 1 downto 0) := (others => '1');
    tstrb    : in  std_logic_vector(G_DATA_BYTES - 1 downto 0) := (others => '1');
    tlast    : in  std_logic                                    := '1';
    tid      : in  std_logic_vector(G_ID_WIDTH - 1 downto 0)   := (others => '0');
    tdest    : in  std_logic_vector(G_DEST_WIDTH - 1 downto 0) := (others => '0');
    tuser    : in  std_logic_vector(G_USER_WIDTH - 1 downto 0) := (others => '0')
  );
end entity axi_stream_sink;

architecture rtl of axi_stream_sink is

  shared variable sv_log : t_beat_log;

  signal s_tready     : std_logic := '1';
  signal s_beat_count : natural   := 0;
  signal s_pkt_count  : natural   := 0;

begin

  tready <= s_tready;

  -- ===========================================================================
  -- TREADY generation
  -- ===========================================================================
  p_tready : process(aclk)
    variable seed1 : positive := 42;
    variable seed2 : positive := 137;
    variable rand  : real;
  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        s_tready <= '0';
      else
        if G_TREADY_ALWAYS then
          s_tready <= '1';
        else
          -- Simple pseudo-random backpressure using ieee.math_real uniform()
          -- Replace seed update with a proper LFSR for synthesis-friendly sim
          ieee.math_real.uniform(seed1, seed2, rand);
          if rand < G_READY_PROB then
            s_tready <= '1';
          else
            s_tready <= '0';
          end if;
        end if;
      end if;
    end if;
  end process p_tready;

  -- ===========================================================================
  -- Beat capture and console logging
  -- ===========================================================================
  p_capture : process(aclk)
    variable v_beat : t_axis_beat;

    -- Convert a 4-bit nibble to a hex character
    function to_hex_char(n : std_logic_vector(3 downto 0)) return character is
      constant C_HEX : string := "0123456789ABCDEF";
    begin
      if is_x(n) then
        return 'X';
      else
        return C_HEX(to_integer(unsigned(n)) + 1);
      end if;
    end function;

    -- Build a big-endian hex string from TDATA
    impure function data_to_hex return string is
      variable result : string(1 to G_DATA_BYTES * 2);
      variable idx    : positive := 1;
    begin
      for byte in G_DATA_BYTES - 1 downto 0 loop
        result(idx)     := to_hex_char(tdata(byte * 8 + 7 downto byte * 8 + 4));
        result(idx + 1) := to_hex_char(tdata(byte * 8 + 3 downto byte * 8 + 0));
        idx := idx + 2;
      end loop;
      return result;
    end function;

  begin
    if rising_edge(aclk) then
      if aresetn = '0' then
        s_beat_count <= 0;
        s_pkt_count  <= 0;

      elsif tvalid = '1' and s_tready = '1' then

        -- Pack the beat into the record (zero-extend to max field widths)
        v_beat.data                          := (others => '0');
        v_beat.data(tdata'range)             := tdata;
        v_beat.keep                          := (others => '0');
        v_beat.keep(tkeep'range)             := tkeep;
        v_beat.strb                          := (others => '0');
        v_beat.strb(tstrb'range)             := tstrb;
        v_beat.last                          := tlast;
        v_beat.id                            := (others => '0');
        v_beat.dest                          := (others => '0');
        v_beat.user                          := (others => '0');
        if G_ID_WIDTH   > 0 then v_beat.id  (tid'range)   := tid;   end if;
        if G_DEST_WIDTH > 0 then v_beat.dest(tdest'range) := tdest; end if;
        if G_USER_WIDTH > 0 then v_beat.user(tuser'range) := tuser; end if;

        -- Push to in-memory log
        sv_log.push(v_beat);

        -- Console output
        report "[" & G_NAME & "]"
          & "  pkt="  & integer'image(s_pkt_count)
          & "  beat=" & integer'image(s_beat_count)
          & "  data=0x" & data_to_hex
          & "  keep=0x" & to_hstring(tkeep)
          & "  strb=0x" & to_hstring(tstrb)
          & "  last=" & std_logic'image(tlast)
          & "  @" & time'image(now)
          severity note;

        -- Packet boundary tracking
        if tlast = '1' then
          report "[" & G_NAME & "] --- Packet " & integer'image(s_pkt_count)
            & " complete: " & integer'image(s_beat_count + 1) & " beat(s)"
            & " @ " & time'image(now) & " ---"
            severity note;
          s_pkt_count  <= s_pkt_count + 1;
          s_beat_count <= 0;
        else
          s_beat_count <= s_beat_count + 1;
        end if;

      end if;
    end if;
  end process p_capture;

end architecture rtl;
