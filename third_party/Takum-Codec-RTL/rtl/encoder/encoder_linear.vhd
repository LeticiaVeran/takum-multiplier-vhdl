-- See LICENSE file for copyright and license details
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_misc.all;
	use ieee.numeric_std.all;

entity encoder_linear is
	generic (
		n : natural range 2 to natural'high
	);
	port (
		sign_bit      : in    std_ulogic;
		exponent      : in    integer range -255 to 254;
		fraction_bits : in    std_ulogic_vector(n - 6 downto 0);
		is_zero       : in    std_ulogic;
		is_nar        : in    std_ulogic;
		takum         : out   std_ulogic_vector(n - 1 downto 0)
	);
end entity encoder_linear;

architecture rtl of encoder_linear is
	signal characteristic : integer range -255 to 254;
begin
	-- negate the exponent depending on the sign_bit to obtain the
	-- characteristic
	characteristic <= exponent when sign_bit = '0' else
	                  to_integer(signed(not(std_ulogic_vector(to_signed(exponent, 9)))));

	postencoder : entity work.postencoder(rtl)
		generic map (
			n => n
		)
		port map (
			sign_bit       => sign_bit,
			characteristic => characteristic,
			mantissa_bits  => fraction_bits,
			is_zero        => is_zero,
			is_nar         => is_nar,
			takum          => takum
		);

end architecture rtl;
