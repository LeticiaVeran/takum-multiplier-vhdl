-- ============================================================================
-- takum_mul_top.vhd
-- The whole multiplier, word in and word out:
--
--     takum -> decoder -> takum_mul_log -> encoder -> takum
--
-- The decoder and the encoder come from the official codec (Takum-Codec-RTL by
-- Laslo Hunhold, ISC licence); only the block in the middle is ours.  The
-- decoder hands over (sign, lbar, zero, NaR), which is exactly what the
-- multiplier consumes, and the encoder turns the result back into bits - it is
-- also where rounding happens.
--
-- Note the port types: the codec uses std_ulogic_vector and the multiplier uses
-- std_logic_vector.  In VHDL-2008 the latter is a subtype of the former, so the
-- two connect directly, with no conversion function.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity takum_mul_top is
  generic (
    N : natural range 5 to natural'high := 16
  );
  port (
    a_takum : in  std_ulogic_vector(N - 1 downto 0);
    b_takum : in  std_ulogic_vector(N - 1 downto 0);
    y_takum : out std_ulogic_vector(N - 1 downto 0)
  );
end entity;

architecture rtl of takum_mul_top is
  signal a_sign, a_zero, a_nar : std_ulogic;
  signal b_sign, b_zero, b_nar : std_ulogic;
  signal y_sign, y_zero, y_nar : std_ulogic;
  signal a_lbar, b_lbar, y_lbar : std_ulogic_vector(N + 3 downto 0);
  signal a_prec, b_prec : natural range 0 to N - 5;   -- unused by the multiplier
begin

  dec_a : entity work.decoder_logarithmic(rtl)
    generic map (n => N)
    port map (takum => a_takum, sign_bit => a_sign,
              barred_logarithmic_value => a_lbar, precision => a_prec,
              is_zero => a_zero, is_nar => a_nar);

  dec_b : entity work.decoder_logarithmic(rtl)
    generic map (n => N)
    port map (takum => b_takum, sign_bit => b_sign,
              barred_logarithmic_value => b_lbar, precision => b_prec,
              is_zero => b_zero, is_nar => b_nar);

  mul : entity work.takum_mul_log(rtl)
    generic map (N => N)
    port map (a_sign => a_sign, a_lbar => a_lbar, a_zero => a_zero, a_nar => a_nar,
              b_sign => b_sign, b_lbar => b_lbar, b_zero => b_zero, b_nar => b_nar,
              y_sign => y_sign, y_lbar => y_lbar, y_zero => y_zero, y_nar => y_nar);

  enc : entity work.encoder_logarithmic(rtl)
    generic map (n => N)
    port map (sign_bit => y_sign, barred_logarithmic_value => y_lbar,
              is_zero => y_zero, is_nar => y_nar, takum => y_takum);

end architecture;
