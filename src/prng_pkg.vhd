library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;

package prng_pkg is

  type rand_t is protected

    -- Seed the generator for a reproducible sequence. Default seeds (1, 1) are valid.
    procedure seed(constant s1 : in positive; constant s2 : in positive);

    -- Random integer in [min, max] inclusive.
    impure function rand_int(min : integer; max : integer) return integer;

    -- Random std_logic_vector of any width, built from 30-bit uniform chunks.
    impure function rand_slv(width : positive) return std_logic_vector;

    -- Random boolean (50/50).
    impure function rand_bool return boolean;

    -- Random std_logic '0' or '1' (50/50).
    impure function rand_sl return std_logic;

    -- Random time in [min_t, max_t], resolved to 1 ns.
    impure function rand_time(min_t : time; max_t : time) return time;

    -- Random byte-aligned address: base + N*align, result as 'width'-bit vector.
    impure function rand_aligned_addr(
      base  : natural;
      size  : positive;
      align : positive;
      width : positive
    ) return std_logic_vector;

    -- Random one-hot vector: exactly one bit set at a random position.
    impure function rand_onehot(width : positive) return std_logic_vector;

    -- Get current seed state. Save before a test and print on failure to enable replay.
    procedure get_seed(variable s1 : out positive; variable s2 : out positive);

    -- Weighted random index: returns 0 to weights'length-1 with probability
    -- proportional to each weight. At least one weight must be > 0.
    impure function rand_weighted(weights : integer_vector) return integer;

    -- Gaussian (normal) random integer clamped to [lo, hi].
    -- Uses Box-Muller transform. stddev = 0.0 returns integer(mean).
    impure function rand_gaussian(mean   : real;
                                  stddev : real;
                                  lo     : integer;
                                  hi     : integer) return integer;

  end protected rand_t;

end package prng_pkg;


package body prng_pkg is

  type rand_t is protected body

    variable v_s1 : positive := 1;
    variable v_s2 : positive := 1;

    -- ------------------------------------------------------------------

    procedure seed(constant s1 : in positive; constant s2 : in positive) is
    begin
      v_s1 := s1;
      v_s2 := s2;
    end procedure;

    -- ------------------------------------------------------------------

    impure function rand_int(min : integer; max : integer) return integer is
      variable r      : real;
      variable result : integer;
    begin
      if min > max then
        print(FATAL, "[random.rand_int] min (" & integer'image(min) &
                     ") > max (" & integer'image(max) & ")");
        return min;
      end if;
      if min = max then return min; end if;
      uniform(v_s1, v_s2, r);
      result := min + integer(r * real(max - min + 1));
      if result > max then result := max; end if;  -- guard: uniform may return 1.0
      return result;
    end function;

    -- ------------------------------------------------------------------

    impure function rand_slv(width : positive) return std_logic_vector is
      variable result    : std_logic_vector(width - 1 downto 0) := (others => '0');
      variable remaining : integer := width;
      variable lo        : integer := 0;
      variable chunk_w   : integer;
      variable chunk_val : integer;
    begin
      -- Build the vector in 30-bit chunks to stay within integer range.
      while remaining > 0 loop
        chunk_w   := remaining when remaining < 30 else 30;
        chunk_val := rand_int(0, 2**chunk_w - 1);
        result(lo + chunk_w - 1 downto lo) :=
          std_logic_vector(to_unsigned(chunk_val, chunk_w));
        lo        := lo + chunk_w;
        remaining := remaining - chunk_w;
      end loop;
      return result;
    end function;

    -- ------------------------------------------------------------------

    impure function rand_bool return boolean is
    begin
      return rand_int(0, 1) = 1;
    end function;

    -- ------------------------------------------------------------------

    impure function rand_sl return std_logic is
    begin
      if rand_int(0, 1) = 1 then return '1'; else return '0'; end if;
    end function;

    -- ------------------------------------------------------------------

    impure function rand_time(min_t : time; max_t : time) return time is
      variable r        : real;
      variable range_ns : integer;
    begin
      if min_t >= max_t then return min_t; end if;
      uniform(v_s1, v_s2, r);
      range_ns := (max_t - min_t) / 1 ns;
      return min_t + integer(r * real(range_ns)) * 1 ns;
    end function;

    -- ------------------------------------------------------------------

    impure function rand_aligned_addr(
      base  : natural;
      size  : positive;
      align : positive;
      width : positive
    ) return std_logic_vector is
      variable num_slots : integer;
      variable slot      : integer;
      variable zero      : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
      num_slots := size / align;
      if num_slots < 1 then
        print(FATAL, "[random.rand_aligned_addr] align (" & integer'image(align) &
                     ") >= size (" & integer'image(size) & ")");
        return zero;
      end if;
      slot := rand_int(0, num_slots - 1);
      return std_logic_vector(to_unsigned(base + slot * align, width));
    end function;

    -- ------------------------------------------------------------------

    impure function rand_onehot(width : positive) return std_logic_vector is
      variable result  : std_logic_vector(width - 1 downto 0) := (others => '0');
      variable bit_pos : integer;
    begin
      bit_pos        := rand_int(0, width - 1);
      result(bit_pos) := '1';
      return result;
    end function;

    -- ------------------------------------------------------------------

    procedure get_seed(variable s1 : out positive; variable s2 : out positive) is
    begin
      s1 := v_s1;
      s2 := v_s2;
    end procedure;

    -- ------------------------------------------------------------------

    impure function rand_weighted(weights : integer_vector) return integer is
      variable total   : integer := 0;
      variable pick    : integer;
      variable running : integer := 0;
    begin
      for i in weights'range loop
        total := total + weights(i);
      end loop;
      if total <= 0 then
        print(FATAL, "[random.rand_weighted] all weights are zero");
        return 0;
      end if;
      pick := rand_int(0, total - 1);
      for i in weights'range loop
        running := running + weights(i);
        if pick < running then
          return i - weights'low;  -- normalise to 0-based position
        end if;
      end loop;
      return weights'length - 1;  -- unreachable; satisfies return requirement
    end function;

    -- ------------------------------------------------------------------

    impure function rand_gaussian(mean   : real;
                                  stddev : real;
                                  lo     : integer;
                                  hi     : integer) return integer is
      variable u1, u2  : real;
      variable z       : real;
      variable result  : real;
      variable clamped : integer;
    begin
      if stddev = 0.0 then
        clamped := integer(mean);
      else
        -- Box-Muller: u1 must be > 0 to avoid log(0)
        loop uniform(v_s1, v_s2, u1); exit when u1 > 0.0; end loop;
        uniform(v_s1, v_s2, u2);
        z      := sqrt(-2.0 * log(u1)) * cos(2.0 * MATH_PI * u2);
        result := mean + stddev * z;
        if    result < real(lo) then clamped := lo;
        elsif result > real(hi) then clamped := hi;
        else                         clamped := integer(result);
        end if;
      end if;
      return clamped;
    end function;

  end protected body rand_t;

end package body prng_pkg;
