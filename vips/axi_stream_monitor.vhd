-- =============================================================================
-- axi_stream_monitor.vhd
-- Passive AXI-Stream monitor — drives no signals, asserts UG934 compliance rules
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_stream_monitor is
  generic (
    G_DATA_BYTES  : positive := 4;    -- Number of data bytes (bus width / 8)
    G_ID_WIDTH    : natural  := 0;    -- TID width  (0 = not present)
    G_DEST_WIDTH  : natural  := 0;    -- TDEST width (0 = not present)
    G_USER_WIDTH  : natural  := 0;    -- TUSER width (0 = not present)
    G_NAME        : string   := "AXIS_MON"
  );
  port (
    aclk     : in std_logic;
    aresetn  : in std_logic;
    tvalid   : in std_logic;
    tready   : in std_logic;
    tdata    : in std_logic_vector(G_DATA_BYTES * 8 - 1 downto 0);
    tkeep    : in std_logic_vector(G_DATA_BYTES - 1 downto 0) := (others => '1');
    tstrb    : in std_logic_vector(G_DATA_BYTES - 1 downto 0) := (others => '1');
    tlast    : in std_logic                                    := '1';
    tid      : in std_logic_vector(G_ID_WIDTH - 1 downto 0)   := (others => '0');
    tdest    : in std_logic_vector(G_DEST_WIDTH - 1 downto 0) := (others => '0');
    tuser    : in std_logic_vector(G_USER_WIDTH - 1 downto 0) := (others => '0')
  );
end entity axi_stream_monitor;

architecture rtl of axi_stream_monitor is

  signal s_tvalid_prev : std_logic := '0';
  signal s_in_packet   : boolean   := false;

begin

  p_monitor : process(aclk)
    variable v_handshake : boolean;
  begin
    if rising_edge(aclk) then
      v_handshake := (tvalid = '1') and (tready = '1');

      -- -----------------------------------------------------------------------
      -- UG934: TVALID must be low during and immediately following reset
      -- -----------------------------------------------------------------------
      if aresetn = '0' then
        if tvalid = '1' then
          report "[" & G_NAME & "] VIOLATION: TVALID asserted while ARESETn low"
            severity failure;
        end if;
        s_in_packet   <= false;
        s_tvalid_prev <= '0';

      else

        -- ---------------------------------------------------------------------
        -- UG934: Once TVALID is asserted it must remain high until handshake
        -- The master must not withdraw TVALID before TREADY is seen
        -- ---------------------------------------------------------------------
        if s_tvalid_prev = '1' and tvalid = '0' and tready = '0' then
          report "[" & G_NAME & "] VIOLATION: TVALID deasserted before handshake (TREADY not seen)"
            severity failure;
        end if;

        -- ---------------------------------------------------------------------
        -- UG934: No X/Z on control signals while TVALID is asserted
        -- ---------------------------------------------------------------------
        if tvalid = '1' then
          if is_x(tlast) then
            report "[" & G_NAME & "] VIOLATION: TLAST is X/Z while TVALID high"
              severity failure;
          end if;
          if is_x(tkeep) then
            report "[" & G_NAME & "] VIOLATION: TKEEP is X/Z while TVALID high"
              severity failure;
          end if;
          if is_x(tstrb) then
            report "[" & G_NAME & "] VIOLATION: TSTRB is X/Z while TVALID high"
              severity failure;
          end if;
          -- TDATA X/Z is a warning only — may be intentional in null byte positions
          if is_x(tdata) then
            report "[" & G_NAME & "] WARNING: TDATA contains X/Z while TVALID high"
              severity warning;
          end if;
        end if;

        -- ---------------------------------------------------------------------
        -- UG934: TKEEP=0 implies TSTRB=0 (null byte cannot be a position byte)
        -- ---------------------------------------------------------------------
        if tvalid = '1' then
          for i in 0 to G_DATA_BYTES - 1 loop
            if tkeep(i) = '0' and tstrb(i) = '1' then
              report "[" & G_NAME & "] VIOLATION: TSTRB(" & integer'image(i) &
                ")=1 but TKEEP(" & integer'image(i) &
                ")=0 — null byte lane cannot be a position byte"
                severity failure;
            end if;
          end loop;
        end if;

        -- ---------------------------------------------------------------------
        -- UG934: Null bytes (TKEEP=0) are only permitted on the last beat
        -- All mid-packet beats must have every TKEEP lane asserted
        -- ---------------------------------------------------------------------
        if tvalid = '1' and tlast = '0' then
          for i in 0 to G_DATA_BYTES - 1 loop
            if tkeep(i) = '0' then
              report "[" & G_NAME & "] VIOLATION: TKEEP(" & integer'image(i) &
                ")=0 on a non-LAST beat — null bytes are only permitted on the final beat"
                severity failure;
            end if;
          end loop;
        end if;

        -- ---------------------------------------------------------------------
        -- UG934: On the last beat, null bytes must occupy the high-order lanes
        -- TKEEP must be contiguous from bit 0 upward (e.g. "0011" legal, "0101" not)
        -- ---------------------------------------------------------------------
        if tvalid = '1' and tlast = '1' then
          declare
            variable seen_null : boolean := false;
          begin
            for i in G_DATA_BYTES - 1 downto 0 loop
              if tkeep(i) = '0' then
                seen_null := true;
              elsif seen_null then
                report "[" & G_NAME & "] VIOLATION: Non-contiguous TKEEP pattern on LAST beat" &
                  " — null bytes must occupy the highest-order lanes only"
                  severity failure;
              end if;
            end loop;
          end;
        end if;

        -- ---------------------------------------------------------------------
        -- Packet tracking
        -- ---------------------------------------------------------------------
        if v_handshake then
          if not s_in_packet then
            s_in_packet <= true;
            report "[" & G_NAME & "] Packet start @ " & time'image(now)
              severity note;
          end if;
          if tlast = '1' then
            s_in_packet <= false;
            report "[" & G_NAME & "] Packet end @ " & time'image(now)
              severity note;
          end if;
        end if;

        s_tvalid_prev <= tvalid;

      end if;  -- aresetn
    end if;  -- rising_edge
  end process p_monitor;

end architecture rtl;
