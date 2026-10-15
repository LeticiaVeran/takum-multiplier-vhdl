-- See LICENSE file for copyright and license details
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_misc.all;
	use ieee.numeric_std.all;

entity decoder_linear is
	generic (
		n : natural range 2 to natural'high
	);
	port (
		takum         : in    std_ulogic_vector(n - 1 downto 0);
		sign_bit      : out   std_ulogic;
		exponent      : out   integer range -255 to 254;
		fraction_bits : out   std_ulogic_vector(n - 6 downto 0);
		precision     : out   natural range 0 to n - 5;
		is_zero       : out   std_ulogic;
		is_nar        : out   std_ulogic
	);
end entity decoder_linear;

architecture rtl of decoder_linear is
begin

	predecoder : entity work.predecoder(rtl)
		generic map (
			n               => n,
			output_exponent => '1'
		)
		port map (
			takum                      => takum,
			sign_bit                   => sign_bit,
			characteristic_or_exponent => exponent,
			mantissa_bits              => fraction_bits,
			precision                  => precision,
			is_zero                    => is_zero,
			is_nar                     => is_nar
		);

end architecture rtl;
