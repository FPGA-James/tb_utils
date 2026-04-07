library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;

package tb_scoreboard_pkg is

  -- Protected scoreboard: push expected values from the drive side,
  -- check actual values from the monitor side.
  -- Supports std_logic_vector, integer, std_logic, and string.
  -- Call final_report at end of sim to print pass/fail summary.
  type scoreboard_t is protected
    procedure push(constant data : in std_logic_vector);
    procedure push(constant data : in integer);
    procedure push(constant data : in std_logic);
    procedure push(constant data : in string);
    procedure check(constant actual : in std_logic_vector; constant msg : in string := "");
    procedure check(constant actual : in integer;          constant msg : in string := "");
    procedure check(constant actual : in std_logic;        constant msg : in string := "");
    procedure check(constant actual : in string;           constant msg : in string := "");
    procedure final_report;
    impure function pass_count return natural;
    impure function fail_count return natural;
    impure function depth return natural;
  end protected scoreboard_t;

end package tb_scoreboard_pkg;

package body tb_scoreboard_pkg is

  -- Node stores the expected value as a serialised string.
  -- Declared in the body — implementation detail, not part of the public API.
  type sb_node_t;
  type sb_node_ptr_t is access sb_node_t;
  type sb_node_t is record
    data : line;           -- serialised expected value (access string)
    nxt  : sb_node_ptr_t;
  end record;

  type scoreboard_t is protected body
    variable head     : sb_node_ptr_t := null;
    variable tail     : sb_node_ptr_t := null;
    variable v_passes : natural := 0;
    variable v_fails  : natural := 0;
    variable v_depth  : natural := 0;

    -- Enqueue a pre-serialised expected string.
    procedure enqueue(constant s : in string) is
      variable node : sb_node_ptr_t;
    begin
      node      := new sb_node_t;
      node.data := new string'(s);
      node.nxt  := null;
      if tail = null then
        head := node;
        tail := node;
      else
        tail.nxt := node;
        tail     := node;
      end if;
      v_depth := v_depth + 1;
    end procedure;

    -- Pop the head node, compare its serialised value against actual_str, log result.
    procedure do_check(constant actual_str : in string; constant msg : in string) is
      variable node : sb_node_ptr_t;
    begin
      if head = null then
        print(ERROR, "[scoreboard] check: queue empty, unexpected data" & (", " & msg));
        v_fails := v_fails + 1;
        return;
      end if;
      node    := head;
      head    := head.nxt;
      if head = null then tail := null; end if;
      v_depth := v_depth - 1;
      if actual_str /= node.data.all then
        print(ERROR, "[scoreboard] check FAIL: expected " & node.data.all &
                     " got " & actual_str & (", " & msg));
        v_fails := v_fails + 1;
      else
        print(DEBUG, "[scoreboard] check PASS" & (", " & msg));
        v_passes := v_passes + 1;
      end if;
      deallocate(node.data);
      deallocate(node);
    end procedure;

    procedure push(constant data : in std_logic_vector) is
    begin
      enqueue("0x" & to_hstring(data));
    end procedure;

    procedure push(constant data : in integer) is
    begin
      enqueue(integer'image(data));
    end procedure;

    procedure push(constant data : in std_logic) is
    begin
      enqueue(to_string(data));
    end procedure;

    procedure push(constant data : in string) is
    begin
      enqueue(data);
    end procedure;

    procedure check(constant actual : in std_logic_vector; constant msg : in string := "") is
    begin
      do_check("0x" & to_hstring(actual), msg);
    end procedure;

    procedure check(constant actual : in integer; constant msg : in string := "") is
    begin
      do_check(integer'image(actual), msg);
    end procedure;

    procedure check(constant actual : in std_logic; constant msg : in string := "") is
    begin
      do_check(to_string(actual), msg);
    end procedure;

    procedure check(constant actual : in string; constant msg : in string := "") is
    begin
      do_check(actual, msg);
    end procedure;

    procedure final_report is
    begin
      print(INFO, "[scoreboard] === Scoreboard Final Report ===");
      print(INFO, "[scoreboard]   PASS: " & integer'image(v_passes));
      print(INFO, "[scoreboard]   FAIL: " & integer'image(v_fails));
      if v_depth > 0 then
        print(ERROR, "[scoreboard]   UNCHECKED items remaining in queue: " & integer'image(v_depth));
      end if;
      if v_fails = 0 and v_depth = 0 then
        print(INFO, "[scoreboard]   Result: ALL PASS");
      else
        print(ERROR, "[scoreboard]   Result: FAILURES DETECTED");
      end if;
    end procedure;

    impure function pass_count return natural is
    begin return v_passes; end function;

    impure function fail_count return natural is
    begin return v_fails; end function;

    impure function depth return natural is
    begin return v_depth; end function;

  end protected body scoreboard_t;

end package body tb_scoreboard_pkg;
