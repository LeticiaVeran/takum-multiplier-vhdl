-- ============================================================================
-- takum_mul_synth_wrapper.vhd
-- Registered wrapper used only for synthesis.
--
-- The multiplier and the chain are purely combinational, and a combinational
-- design on its own gives no useful timing report: there is no path between
-- two registers for the tool to measure. This wrapper registers the inputs and
-- the output, so the critical path reported by Vivado is exactly the logic
-- under study, from one flip-flop to the next.
--
-- It also keeps the design from being optimised away. Without the registers,
-- and without pins to drive, synthesis would be free to delete everything.
--
-- Two configurations, selected by the generic USE_CHAIN:
--   0 - the multiplier alone, on the internal representation (S, lbar)
--   1 - the whole chain: takum -> decoder -> multiplier -> encoder -> takum
-- (An integer rather than a boolean, so it can be set from Vivado's GUI and
-- Tcl the same way as N, with no doubt about how a boolean is spelled.)
--
-- Every port exists in both configurations; the unused ones are tied off and
-- removed by synthesis. That is 6N + 22 ports, more than the 210 pins of the
-- Nexys A7 from N = 32 on, which is why build.tcl synthesises out of context
-- (no pins at all) - see vivado/README.md.
--
-- Measure both: the first is the contribution of this work, the second is what
-- a user of the format would actually instantiate.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity takum_mul_synth_wrapper is
  generic (
    N         : natural := 16;                -- takum width
    USE_CHAIN : natural range 0 to 1 := 1     -- 0: multiplier only; 1: full chain
  );
  port (
    clk : in  std_ulogic;

    -- takum words, used when USE_CHAIN = 1
    a_takum : in  std_ulogic_vector(N - 1 downto 0);
    b_takum : in  std_ulogic_vector(N - 1 downto 0);
    y_takum : out std_ulogic_vector(N - 1 downto 0);

    -- internal representation, used when USE_CHAIN = 0
    a_sign : in  std_ulogic;
    a_lbar : in  std_ulogic_vector(N + 3 downto 0);
    a_zero : in  std_ulogic;
    a_nar  : in  std_ulogic;
    b_sign : in  std_ulogic;
    b_lbar : in  std_ulogic_vector(N + 3 downto 0);
    b_zero : in  std_ulogic;
    b_nar  : in  std_ulogic;
    y_sign : out std_ulogic;
    y_lbar : out std_ulogic_vector(N + 3 downto 0);
    y_zero : out std_ulogic;
    y_nar  : out std_ulogic
  );
end entity;

architecture rtl of takum_mul_synth_wrapper is
  -- input registers
  signal a_takum_r, b_takum_r : std_ulogic_vector(N - 1 downto 0);
  signal a_lbar_r, b_lbar_r   : std_ulogic_vector(N + 3 downto 0);
  signal a_sign_r, a_zero_r, a_nar_r : std_ulogic;
  signal b_sign_r, b_zero_r, b_nar_r : std_ulogic;

  -- combinational results
  signal y_takum_c : std_ulogic_vector(N - 1 downto 0);
  signal y_lbar_c  : std_ulogic_vector(N + 3 downto 0);
  signal y_sign_c, y_zero_c, y_nar_c : std_ulogic;
begin

  -- ---- input registers ------------------------------------------------------
  process (clk) is
  begin
    if rising_edge(clk) then
      a_takum_r <= a_takum;
      b_takum_r <= b_takum;
      a_sign_r <= a_sign; a_lbar_r <= a_lbar; a_zero_r <= a_zero; a_nar_r <= a_nar;
      b_sign_r <= b_sign; b_lbar_r <= b_lbar; b_zero_r <= b_zero; b_nar_r <= b_nar;
    end if;
  end process;

  -- ---- design under measurement --------------------------------------------
  gen_chain : if USE_CHAIN = 1 generate
    dut : entity work.takum_mul_top(rtl)
      generic map (N => N)
      port map (a_takum => a_takum_r, b_takum => b_takum_r, y_takum => y_takum_c);

    y_lbar_c <= (others => '0');
    y_sign_c <= '0';
    y_zero_c <= '0';
    y_nar_c  <= '0';
  else generate
    dut : entity work.takum_mul_log(rtl)
      generic map (N => N)
      port map (a_sign => a_sign_r, a_lbar => a_lbar_r,
                a_zero => a_zero_r, a_nar => a_nar_r,
                b_sign => b_sign_r, b_lbar => b_lbar_r,
                b_zero => b_zero_r, b_nar => b_nar_r,
                y_sign => y_sign_c, y_lbar => y_lbar_c,
                y_zero => y_zero_c, y_nar => y_nar_c);

    y_takum_c <= (others => '0');
  end generate;

  -- ---- output registers -----------------------------------------------------
  process (clk) is
  begin
    if rising_edge(clk) then
      y_takum <= y_takum_c;
      y_lbar  <= y_lbar_c;
      y_sign  <= y_sign_c;
      y_zero  <= y_zero_c;
      y_nar   <= y_nar_c;
    end if;
  end process;

end architecture;
