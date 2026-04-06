-- **Usage**
--
-- ```vhdl
-- shared variable seq : t_sequence;
--
-- -- Walking-ones pattern across an 8-bit data bus
-- seq.set_mode("WALK1");
-- seq.set_width(8);
-- seq.set_range(0, 255);
--
-- for i in 0 to 7 loop
--     data_in <= std_logic_vector(to_unsigned(seq.next_val, 8));
--     wait until rising_edge(clk);
-- end loop;
--
-- -- Switch to incrementing for a boundary-value sweep
-- seq.set_mode("INC");
-- seq.set_range(0, 255);
-- seq.reset;
--
-- for i in 0 to 255 loop
--     data_in <= std_logic_vector(to_unsigned(seq.next_val, 8));
--     wait until rising_edge(clk);
-- end loop;
-- ```

package sequence_pkg is
	type t_sequence is protected
    	procedure set_mode(m : string);
    	procedure set_range(lo, hi : integer);
    	procedure set_width(w : natural);
    	impure function next_val return integer;
    	procedure reset;
	end protected;
end package sequence_pkg;

package body sequence_pkg is 
type t_sequence is protected body
    -- Modes: "INC", "DEC", "WALK1", "WALK0", "ALT", "CONST"
    variable mode    : string(1 to 6) := "INC   ";
    variable lo_val  : integer := 0;
    variable hi_val  : integer := 255;
    variable current : integer := 0;
    variable width   : natural := 8;
    variable toggle  : boolean := false;

    procedure set_mode(m : string) is
        variable padded : string(1 to 6) := (others => ' ');
    begin
        padded(1 to m'length) := m;
        mode    := padded;
        current := lo_val;
        toggle  := false;
    end procedure;

    procedure set_range(lo, hi : integer) is
    begin
        lo_val  := lo;
        hi_val  := hi;
        current := lo;
    end procedure;

    procedure set_width(w : natural) is begin width := w; end procedure;

    impure function next_val return integer is
        variable ret : integer;
    begin
        ret := current;
        if mode = "INC   " then
            current := lo_val when current >= hi_val else current + 1;
        elsif mode = "DEC   " then
            current := hi_val when current <= lo_val else current - 1;
        elsif mode = "WALK1 " then
            current := 1 when current = 0 or current >= 2**(width-1) else current * 2;
        elsif mode = "WALK0 " then
            current := 2**(width-1) when current <= 1 else current / 2;
        elsif mode = "ALT   " then
            current := hi_val when toggle else lo_val;
            toggle  := not toggle;
        end if;
        return ret;
    end function;

    procedure reset is
    begin
        current := lo_val;
        toggle  := false;
    end procedure;
end protected body;
end package body sequence_pkg;


