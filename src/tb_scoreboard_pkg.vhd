library ieee;
use ieee.std_logic_1164.all;
library tb_utils;
use tb_utils.tb_pkg.all;

package tb_scoreboard_pkg is

  -- Singly-linked list node for the internal queue.
  type slv_node_t;
  type slv_node_ptr_t is access slv_node_t;
  type slv_node_t is record
    data : std_logic_vector(255 downto 0);  -- wide enough for most buses
    len  : natural;                          -- actual width in bits
    next : slv_node_ptr_t;
  end record;

  -- Protected scoreboard: push expected values from the drive side,
  -- check actual values from the monitor side.
  -- Call final_report at end of sim to print pass/fail summary.
  type scoreboard_t is protected
    procedure push(constant data : in std_logic_vector);
    procedure check(constant actual : in std_logic_vector; constant msg : in string := "");
    procedure final_report;
    impure function pass_count return natural;
    impure function fail_count return natural;
    impure function depth return natural;
  end protected scoreboard_t;

end package tb_scoreboard_pkg;

package body tb_scoreboard_pkg is

  type scoreboard_t is protected body
    variable head     : slv_node_ptr_t := null;
    variable tail     : slv_node_ptr_t := null;
    variable v_passes : natural := 0;
    variable v_fails  : natural := 0;
    variable v_depth  : natural := 0;

    procedure push(constant data : in std_logic_vector) is
      variable node : slv_node_ptr_t;
    begin
      node := new slv_node_t;
      node.data(data'length - 1 downto 0) := data;
      node.len  := data'length;
      node.next := null;
      if tail = null then
        head := node;
        tail := node;
      else
        tail.next := node;
        tail := node;
      end if;
      v_depth := v_depth + 1;
    end procedure;

    procedure check(constant actual : in std_logic_vector; constant msg : in string := "") is
      variable node     : slv_node_ptr_t;
      variable expected : std_logic_vector(actual'range);
    begin
      if head = null then
        print(ERROR, "scoreboard.check: queue empty, unexpected data" & (", " & msg));
        v_fails := v_fails + 1;
        return;
      end if;
      node := head;
      expected := node.data(actual'length - 1 downto 0);
      head := head.next;
      if head = null then tail := null; end if;
      v_depth := v_depth - 1;
      deallocate(node);
      if actual /= expected then
        print(ERROR, "scoreboard.check FAIL: expected 0x" & to_hstring(expected) &
                     " got 0x" & to_hstring(actual) & (", " & msg));
        v_fails := v_fails + 1;
      else
        print(DEBUG, "scoreboard.check PASS" & (", " & msg));
        v_passes := v_passes + 1;
      end if;
    end procedure;

    procedure final_report is
    begin
      print(INFO, "=== Scoreboard Final Report ===");
      print(INFO, "  PASS: " & integer'image(v_passes));
      print(INFO, "  FAIL: " & integer'image(v_fails));
      if v_depth > 0 then
        print(ERROR, "  UNCHECKED items remaining in queue: " & integer'image(v_depth));
      end if;
      if v_fails = 0 and v_depth = 0 then
        print(INFO, "  Result: ALL PASS");
      else
        print(ERROR, "  Result: FAILURES DETECTED");
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
