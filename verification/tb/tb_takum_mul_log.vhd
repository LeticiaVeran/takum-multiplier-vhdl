-- ============================================================================
-- tb_takum_mul_log.vhd
-- Self-checking testbench for the stand-alone multiplier.
--
-- It reads vec_mul_<N>.txt, written by takum_model.py (mul-vectors, or
-- demo-vectors for nine readable cases), applies one vector per nanosecond and
-- compares every output field with the expected value from the reference model.
-- The last report line is the result: MISMATCHES=0 means the run passed.
--
-- Normally run through:  python3 run_tests.py mul 16
-- By hand, inside build/: ghdl -r --std=08 tb_takum_mul_log -gN=16
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_takum_mul_log is
  generic (N : natural := 16);
end entity;

architecture sim of tb_takum_mul_log is
  -- The file name is derived from N instead of being a second generic: GHDL
  -- would otherwise use the default value of one generic while overriding the
  -- other, and we would silently read the vectors of a different width.
  constant VEC_FILE : string := "vec_mul_" & integer'image(N) & ".txt";

  signal a_sign, a_zero, a_nar, b_sign, b_zero, b_nar : std_logic := '0';
  signal y_sign, y_zero, y_nar : std_logic;
  signal a_lbar, b_lbar, y_lbar : std_logic_vector(N+3 downto 0) := (others => '0');
begin
  dut : entity work.takum_mul_log
    generic map (N => N)
    port map (a_sign, a_lbar, a_zero, a_nar, b_sign, b_lbar, b_zero, b_nar,
              y_sign, y_lbar, y_zero, y_nar);

  process
    file fv : text;
    variable ln : line;
    variable sa, za, na, sb, zb, nb, se, ze, ne : std_logic;
    variable la, lb, le : std_logic_vector(N+3 downto 0);
    variable n_ok, n_err : natural := 0;
  begin
    -- Opened here, during simulation, rather than in the declarative part:
    -- declarations are elaborated before the generic override is applied.
    file_open(fv, VEC_FILE, read_mode);

    while not endfile(fv) loop
      readline(fv, ln);
      -- One line holds operand a, operand b and the expected result y.
      read(ln, sa); read(ln, la); read(ln, za); read(ln, na);
      read(ln, sb); read(ln, lb); read(ln, zb); read(ln, nb);
      read(ln, se); read(ln, le); read(ln, ze); read(ln, ne);

      a_sign <= sa; a_lbar <= la; a_zero <= za; a_nar <= na;
      b_sign <= sb; b_lbar <= lb; b_zero <= zb; b_nar <= nb;
      wait for 1 ns;                      -- let the combinational logic settle

      if y_sign = se and y_lbar = le and y_zero = ze and y_nar = ne then
        n_ok := n_ok + 1;
      else
        n_err := n_err + 1;
        if n_err <= 10 then                -- only the first few, to stay readable
          report "MISMATCH: la=" & to_hstring(la) & " lb=" & to_hstring(lb) &
                 " expected=" & to_hstring(le) & " got=" & to_hstring(y_lbar)
            severity error;
        end if;
      end if;
    end loop;

    report "N=" & integer'image(N) & " OK=" & integer'image(n_ok) &
           " MISMATCHES=" & integer'image(n_err) severity note;
    wait;                                  -- stop this process for good
  end process;
end architecture;
