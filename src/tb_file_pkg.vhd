library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;
library tb_utils;
use tb_utils.tb_utils_pkg.all;

package tb_file_pkg is

  -- Compare two text files line by line. Reports every mismatch; prints PASS or FAIL summary.
  -- Blank lines are skipped only when both files have a blank line at the same position.
  procedure file_compare(
    constant filename_a : in string;
    constant filename_b : in string
  );

end package tb_file_pkg;

package body tb_file_pkg is

  procedure file_compare(
    constant filename_a : in string;
    constant filename_b : in string
  ) is
    file     fa, fb     : text;
    variable fsa, fsb   : file_open_status;
    variable la, lb     : line;
    variable mismatches : integer := 0;
    variable line_num   : integer := 0;
  begin
    file_open(fsa, fa, filename_a, read_mode);
    if fsa /= open_ok then
      print(ERROR, "file_compare: cannot open " & filename_a);
      return;
    end if;
    file_open(fsb, fb, filename_b, read_mode);
    if fsb /= open_ok then
      print(ERROR, "file_compare: cannot open " & filename_b);
      file_close(fa);
      return;
    end if;

    while not endfile(fa) and not endfile(fb) loop
      readline(fa, la);
      readline(fb, lb);
      line_num := line_num + 1;
      -- skip only when both lines are blank simultaneously
      next when la'length = 0 and lb'length = 0;
      if la.all /= lb.all then
        print(ERROR, "file_compare: line " & integer'image(line_num) &
              ": a=" & la.all & " b=" & lb.all);
        mismatches := mismatches + 1;
      end if;
    end loop;

    if not endfile(fa) or not endfile(fb) then
      print(ERROR, "file_compare: files have different line counts");
      mismatches := mismatches + 1;
    end if;

    file_close(fa);
    file_close(fb);

    if mismatches = 0 then
      print(INFO, "file_compare: PASS -- files match (" &
            integer'image(line_num) & " lines)");
    else
      print(ERROR, "file_compare: FAIL -- " &
            integer'image(mismatches) & " mismatches");
    end if;
  end procedure;

end package body tb_file_pkg;
