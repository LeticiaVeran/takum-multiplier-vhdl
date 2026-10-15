-- See LICENSE file for copyright and license details
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_misc.all;
	use ieee.numeric_std.all;

entity encoder_logarithmic is
	generic (
		n : natural range 2 to natural'high
	);
	port (
		sign_bit                 : in    std_ulogic;
		barred_logarithmic_value : in    std_ulogic_vector(n + 3 downto 0); -- 9 bits integer, n-5 bits fractional
		is_zero                  : in    std_ulogic;
		is_nar                   : in    std_ulogic;
		takum                    : out   std_ulogic_vector(n - 1 downto 0)
	);
end entity encoder_logarithmic;

architecture rtl of encoder_logarithmic is
begin

	-- the barred logarithmic value is just c + m, i.e. the concatenation
	-- of the characteristic signed integer bits and the mantissa bits.
	postencoder : entity work.postencoder(rtl)
		generic map (
			n => n
		)
		port map (
			sign_bit       => sign_bit,
			characteristic => to_integer(signed(barred_logarithmic_value(n + 3 downto n - 5))),
			mantissa_bits  => barred_logarithmic_value(n - 6 downto 0),
			is_zero        => is_zero,
			is_nar         => is_nar,
			takum          => takum
		);

end architecture rtl;
