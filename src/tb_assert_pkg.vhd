library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library tb_utils;
use tb_utils.tb_pkg.all;

package tb_assert_pkg is

  -- Check two std_logic_vector values are equal.
  -- On failure: prints ERROR with expected/actual in hex, does not stop sim.
  procedure check_equal(
    constant actual   : in std_logic_vector;
    constant expected : in std_logic_vector;
    constant msg      : in string := ""
  );

  -- Check two integers are equal.
  procedure check_equal(
    constant actual   : in integer;
    constant expected : in integer;
    constant msg      : in string := ""
  );

  -- Check a single std_logic value.
  procedure check_equal(
    constant actual   : in std_logic;
    constant expected : in std_logic;
    constant msg      : in string := ""
  );

  -- Check a boolean condition is true.
  procedure check_true(
    constant condition : in boolean;
    constant msg       : in string := ""
  );

  -- Check signal remains stable for the given duration (sampled every 1 ns).
  -- Must be called from a process; blocks for duration.
  procedure check_stable(
    signal   sig      : in std_logic_vector;
    constant duration : in time;
    constant msg      : in string := ""
  );

end package tb_assert_pkg;

package body tb_assert_pkg is

  procedure check_equal(
    constant actual   : in std_logic_vector;
    constant expected : in std_logic_vector;
    constant msg      : in string := ""
  ) is
  begin
    if actual /= expected then
      print(ERROR, "[assert.check_equal] FAIL: expected 0x" & to_hstring(expected) &
                   " got 0x" & to_hstring(actual) &
                   (", " & msg));
    else
      print(DEBUG, "[assert.check_equal] PASS" & (", " & msg));
    end if;
  end procedure;

  procedure check_equal(
    constant actual   : in integer;
    constant expected : in integer;
    constant msg      : in string := ""
  ) is
  begin
    if actual /= expected then
      print(ERROR, "[assert.check_equal] FAIL: expected " & integer'image(expected) &
                   " got " & integer'image(actual) & (", " & msg));
    else
      print(DEBUG, "[assert.check_equal] PASS" & (", " & msg));
    end if;
  end procedure;

  procedure check_equal(
    constant actual   : in std_logic;
    constant expected : in std_logic;
    constant msg      : in string := ""
  ) is
  begin
    if actual /= expected then
      print(ERROR, "[assert.check_equal] FAIL: expected " & std_logic'image(expected) &
                   " got " & std_logic'image(actual) & (", " & msg));
    else
      print(DEBUG, "[assert.check_equal] PASS" & (", " & msg));
    end if;
  end procedure;

  procedure check_true(constant condition : in boolean; constant msg : in string := "") is
  begin
    if not condition then
      print(ERROR, "[assert.check_true] FAIL: condition is false" & (", " & msg));
    else
      print(DEBUG, "[assert.check_true] PASS" & (", " & msg));
    end if;
  end procedure;

  procedure check_stable(
    signal   sig      : in std_logic_vector;
    constant duration : in time;
    constant msg      : in string := ""
  ) is
    constant initial : std_logic_vector(sig'range) := sig;
    variable elapsed : time := 0 ns;
    constant step    : time := 1 ns;
  begin
    while elapsed < duration loop
      wait for step;
      elapsed := elapsed + step;
      if sig /= initial then
        print(ERROR, "[assert.check_stable] FAIL: signal changed at " & time'image(now) & (", " & msg));
        return;
      end if;
    end loop;
    print(DEBUG, "[assert.check_stable] PASS" & (", " & msg));
  end procedure;

end package body tb_assert_pkg;
