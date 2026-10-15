-- ============================================================================
-- tb_takum_mul_top.vhd
-- Testbench for the full chain (takum word in, takum word out).
--
-- Unlike the multiplier testbench, this one does not decide pass or fail: it
-- reads the stimulus from pairs_<N>.txt, writes the results to out_<N>.txt and
-- lets takum_model.py (check, or check-local for large N) do the comparison in
-- Python, where exact fractions and the format definition are easy to work with.
--
-- Normally run through:  python3 run_tests.py chain 16
-- By hand, inside build/: ghdl -r --std=08 tb_takum_mul_top -gN=16
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

entity tb_takum_mul_top is
  generic (N : natural := 16);
end entity;

architecture sim of tb_takum_mul_top is
  -- Names derived from N, for the same reason as in the other testbench.
  constant IN_FILE  : string := "pairs_" & integer'image(N) & ".txt";
  constant OUT_FILE : string := "out_" & integer'image(N) & ".txt";

  signal a, b, y : std_ulogic_vector(N - 1 downto 0) := (others => '0');
begin
  dut : entity work.takum_mul_top(rtl)
    generic map (N => N)
    port map (a_takum => a, b_takum => b, y_takum => y);

  process
    file fi : text;
    file fo : text;
    variable li, lo : line;
    variable va, vb : std_ulogic_vector(N - 1 downto 0);
  begin
    file_open(fi, IN_FILE, read_mode);
    file_open(fo, OUT_FILE, write_mode);

    while not endfile(fi) loop
      readline(fi, li);
      read(li, va); read(li, vb);          -- two takum words per line
      a <= va; b <= vb;
      wait for 1 ns;                       -- let the chain settle
      write(lo, y);
      writeline(fo, lo);
    end loop;

    file_close(fi); file_close(fo);
    report "full chain: all vectors processed" severity note;
    wait;
  end process;
end architecture;
