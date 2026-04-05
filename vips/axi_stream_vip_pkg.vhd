-- =============================================================================
-- axi_stream_vip_pkg.vhd
-- Shared types, transaction record, and protected log buffer for AXI-Stream VIP
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package axi_stream_vip_pkg is

  -- One captured beat (fields zero-extended to maximum supported widths)
  type t_axis_beat is record
    data  : std_logic_vector(127 downto 0);  -- max 128-bit / 16-byte data bus
    keep  : std_logic_vector(15 downto 0);
    strb  : std_logic_vector(15 downto 0);
    last  : std_logic;
    id    : std_logic_vector(7 downto 0);
    dest  : std_logic_vector(7 downto 0);
    user  : std_logic_vector(7 downto 0);
  end record;

  constant C_MAX_LOG : natural := 4096;

  -- Protected type: thread-safe beat log accessible across processes
  type t_beat_log is protected
    procedure push(beat : t_axis_beat);
    impure function size return natural;
    impure function get(idx : natural) return t_axis_beat;
    procedure clear;
  end protected;

end package axi_stream_vip_pkg;

package body axi_stream_vip_pkg is

  type t_beat_log is protected body
    type t_beat_array is array (0 to C_MAX_LOG - 1) of t_axis_beat;
    variable store : t_beat_array;
    variable count : natural := 0;

    procedure push(beat : t_axis_beat) is
    begin
      if count < C_MAX_LOG then
        store(count) := beat;
        count := count + 1;
      else
        report "[AXIS_SINK] Log full — oldest entries lost" severity warning;
      end if;
    end procedure;

    impure function size return natural is
    begin return count; end function;

    impure function get(idx : natural) return t_axis_beat is
    begin return store(idx); end function;

    procedure clear is
    begin count := 0; end procedure;

  end protected body;

end package body axi_stream_vip_pkg;
