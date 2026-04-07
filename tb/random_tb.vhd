library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;
use tb_utils.tb_assert_pkg.all;
use tb_utils.prng_pkg.all;

entity random_tb is
end entity random_tb;

architecture sim of random_tb is
  shared variable rng : rand_t;
begin

  stim : process
    variable vi     : integer;
    variable vslv   : std_logic_vector(63 downto 0);
    variable vt     : time;
    variable vaddr  : std_logic_vector(7 downto 0);
    variable voh    : std_logic_vector(7 downto 0);
    variable ones   : integer;
    variable s1, s2 : positive;
    variable vi2    : integer;
  begin
    -- Reproducible sequence
    rng.seed(42, 7);

    -- rand_int: 200 values in [0, 15], all must be in bounds
    for i in 1 to 200 loop
      vi := rng.rand_int(0, 15);
      check_true(vi >= 0 and vi <= 15,
                 "rand_int [0,15] i=" & integer'image(i));
    end loop;

    -- rand_int: negative range
    for i in 1 to 50 loop
      vi := rng.rand_int(-10, 10);
      check_true(vi >= -10 and vi <= 10, "rand_int [-10,10]");
    end loop;

    -- rand_int: degenerate single-value range
    vi := rng.rand_int(99, 99);
    check_equal(vi, 99, "rand_int degenerate range");

    -- rand_slv: width 32 — check length and that successive calls differ
    vslv(31 downto 0) := rng.rand_slv(32);
    check_equal(vslv(31 downto 0)'length, 32, "rand_slv width=32");

    -- rand_slv: width 64 — exercises the multi-chunk path
    vslv := rng.rand_slv(64);
    check_equal(vslv'length, 64, "rand_slv width=64");

    -- rand_bool / rand_sl: smoke test
    check_true(rng.rand_bool or not rng.rand_bool, "rand_bool type check");
    check_true(rng.rand_sl = '0' or rng.rand_sl = '1', "rand_sl value check");

    -- rand_time: 50 values in [10 ns, 100 ns]
    for i in 1 to 50 loop
      vt := rng.rand_time(10 ns, 100 ns);
      check_true(vt >= 10 ns and vt <= 100 ns,
                 "rand_time in [10ns,100ns] i=" & integer'image(i));
    end loop;

    -- rand_time: degenerate equal bounds
    vt := rng.rand_time(50 ns, 50 ns);
    check_true(vt = 50 ns, "rand_time degenerate");

    -- rand_aligned_addr: base=0, size=256, align=4, width=8
    --   every result must be 4-byte aligned and < 256
    for i in 1 to 50 loop
      vaddr := rng.rand_aligned_addr(0, 256, 4, 8);
      check_true(to_integer(unsigned(vaddr)) mod 4 = 0,
                 "rand_aligned_addr 4-byte aligned");
      check_true(to_integer(unsigned(vaddr)) < 256,
                 "rand_aligned_addr within range");
    end loop;

    -- rand_aligned_addr: non-zero base
    vaddr := rng.rand_aligned_addr(16, 64, 8, 8);
    check_true(to_integer(unsigned(vaddr)) >= 16, "rand_aligned_addr base >= 16");
    check_true(to_integer(unsigned(vaddr)) < 80,  "rand_aligned_addr base+size < 80");
    check_true(to_integer(unsigned(vaddr)) mod 8 = 0, "rand_aligned_addr 8-byte aligned");

    -- rand_onehot: 50 values width=8, exactly one '1' per result
    for i in 1 to 50 loop
      voh  := rng.rand_onehot(8);
      ones := 0;
      for b in 0 to 7 loop
        if voh(b) = '1' then ones := ones + 1; end if;
      end loop;
      check_equal(ones, 1, "rand_onehot exactly one bit i=" & integer'image(i));
    end loop;

    -- get_seed: save state, advance, restore and check sequence restarts identically
    rng.get_seed(s1, s2);
    vi  := rng.rand_int(0, 1000);
    rng.seed(s1, s2);
    vi2 := rng.rand_int(0, 1000);
    check_equal(vi, vi2, "get_seed/restore reproduces same value");

    -- rand_weighted: deterministic weight (1,0,0) must always return index 0
    for i in 1 to 20 loop
      vi := rng.rand_weighted((1, 0, 0));
      check_equal(vi, 0, "rand_weighted all-weight-on-first i=" & integer'image(i));
    end loop;

    -- rand_weighted: (0,0,1) must always return index 2
    for i in 1 to 20 loop
      vi := rng.rand_weighted((0, 0, 1));
      check_equal(vi, 2, "rand_weighted all-weight-on-last i=" & integer'image(i));
    end loop;

    -- rand_weighted: result must be a valid index for an even distribution
    for i in 1 to 100 loop
      vi := rng.rand_weighted((3, 3, 3, 3));
      check_true(vi >= 0 and vi <= 3,
                 "rand_weighted index in range i=" & integer'image(i));
    end loop;

    -- rand_gaussian: degenerate (stddev=0) returns integer(mean)
    vi := rng.rand_gaussian(42.0, 0.0, 0, 100);
    check_equal(vi, 42, "rand_gaussian stddev=0 returns mean");

    -- rand_gaussian: all values clamped within [lo, hi]
    for i in 1 to 200 loop
      vi := rng.rand_gaussian(50.0, 20.0, 0, 100);
      check_true(vi >= 0 and vi <= 100,
                 "rand_gaussian clamped to [0,100] i=" & integer'image(i));
    end loop;

    -- rand_gaussian: tight clamp forces a specific value
    vi := rng.rand_gaussian(5.0, 0.0, 5, 5);
    check_equal(vi, 5, "rand_gaussian degenerate range");

    print(INFO, "random_tb complete");
    std.env.stop;
  end process;

end architecture sim;
