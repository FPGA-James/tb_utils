library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_pkg.all;

package flow_ctrl_pkg is

type t_flow_controller is protected
    procedure set_mode(mode : string);
    procedure set_throttle(percent : natural);
    procedure set_pattern(pat : std_logic_vector);
    impure function ready_this_cycle return boolean;
end protected;

end package flow_ctrl_pkg;

package body flow_ctrl_pkg is
type t_flow_controller is protected body
    -- Modes: "ALWAYS", "NEVER", "RANDOM", "PATTERN", "THROTTLE"
    variable mode       : string(1 to 8) := "ALWAYS  ";
    variable throttle   : natural := 50;
    variable pattern    : std_logic_vector(15 downto 0) := x"AAAA";
    variable pat_idx    : natural := 0;
    variable prng_state : integer := 99991;

    procedure set_mode(m : string) is
        variable padded : string(1 to 8) := (others => ' ');
    begin
        padded(1 to m'length) := m;
        mode    := padded;
        pat_idx := 0;
    end procedure;

    procedure set_throttle(percent : natural) is
    begin
        throttle := percent;
    end procedure;

    procedure set_pattern(pat : std_logic_vector) is
    begin
        pattern(pat'length-1 downto 0) := pat;
        pat_idx := 0;
    end procedure;

    impure function rand_step return integer is
    begin
        prng_state := (prng_state * 1103515245 + 12345) mod 2147483647;
        return prng_state;
    end function;

    impure function ready_this_cycle return boolean is
        variable b : std_logic;
    begin
        if mode = "ALWAYS  " then return true;
        elsif mode = "NEVER   " then return false;
        elsif mode = "RANDOM  " then
            return (rand_step mod 100) < throttle;
        elsif mode = "PATTERN " then
            b       := pattern(pat_idx mod 16);
            pat_idx := pat_idx + 1;
            return b = '1';
        elsif mode = "THROTTLE" then
            return (rand_step mod 100) < throttle;
        end if;
        return true;
    end function;
end protected body;
end package body flow_ctrl_pkg;


