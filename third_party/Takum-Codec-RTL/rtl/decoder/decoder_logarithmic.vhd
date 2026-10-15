-- See LICENSE file for copyright and license details
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_misc.all;
	use ieee.numeric_std.all;

entity decoder_logarithmic is
	generic (
		n : natural range 2 to natural'high
	);
	port (
		takum                    : in    std_ulogic_vector(n - 1 downto 0);
		sign_bit                 : out   std_ulogic;
		barred_logarithmic_value : out   std_ulogic_vector(n + 3 downto 0); -- 9 bits integer, n-5 bits fractional
		precision                : out   natural range 0 to n - 5;
		is_zero                  : out   std_ulogic;
		is_nar                   : out   std_ulogic
	);
end entity decoder_logarithmic;

architecture rtl of decoder_logarithmic is
	signal characteristic : integer range -255 to 254;
	signal mantissa_bits  : std_ulogic_vector(n - 6 downto 0);
begin

	predecoder : entity work.predecoder(rtl)
		generic map (
			n               => n,
			output_exponent => '0'
		)
		port map (
			takum                      => takum,
			sign_bit                   => sign_bit,
			characteristic_or_exponent => characteristic,
			mantissa_bits              => mantissa_bits,
			precision                  => precision,
			is_zero                    => is_zero,
			is_nar                     => is_nar
		);

	-- the barred logarithmic value is just c + m, i.e. the concatenation
	-- of the characteristic signed integer bits and the mantissa bits
	barred_logarithmic_value <= std_ulogic_vector(to_signed(characteristic, 9)) & mantissa_bits;
end architecture rtl;
