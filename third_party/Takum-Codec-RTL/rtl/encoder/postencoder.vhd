-- See LICENSE file for copyright and license details
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.std_logic_misc.all;
	use ieee.numeric_std.all;

entity postencoder is
	generic (
		n : natural range 2 to natural'high
	);
	port (
		sign_bit       : in    std_ulogic;
		characteristic : in    integer range -255 to 254;
		mantissa_bits  : in    std_ulogic_vector(n - 6 downto 0);
		is_zero        : in    std_ulogic;
		is_nar         : in    std_ulogic;
		takum          : out   std_ulogic_vector(n - 1 downto 0)
	);
end entity postencoder;

architecture rtl of postencoder is
	signal direction_bit            : std_ulogic;
	signal characteristic_precursor : std_ulogic_vector(7 downto 0);
	signal regime                   : natural range 0 to 7;
	signal extended_takum           : std_ulogic_vector(n + 6 downto 0);
	signal takum_rounded            : std_ulogic_vector(n - 1 downto 0);
	signal round_up_overflows       : std_ulogic;
	signal round_down_underflows    : std_ulogic;
begin
	-- direction bit is 1 when characteristic >= 0 holds
	direction_bit <= not to_signed(characteristic, 9)(8);

	predict_underflow_overflow : block is
		signal   mantissa_bits_crop      : std_ulogic_vector(n - 12 downto 0);
		constant mantissa_bits_crop_zero : std_ulogic_vector(n - 12 downto 0) := (others => '0');
		constant mantissa_bits_crop_one  : std_ulogic_vector(n - 12 downto 0) := (others => '1');

		type characteristic_bound_type is array (2 to 11) of integer range -254 to 253;

		constant characteristic_underflow_bound : characteristic_bound_type :=
		(
		  -1,
		  -16,
		  -64,
		  -128,
		  -192,
		  -224,
		  -240,
		  -248,
		  -252,
		  -254
		);

		constant characteristic_overflow_bound : characteristic_bound_type :=
		(
		  0,
		  15,
		  63,
		  127,
		  191,
		  223,
		  239,
		  247,
		  251,
		  253
		);
	begin
		mantissa_bits_crop <= mantissa_bits(n - 6 downto 6);

		check_characteristic : process (characteristic, mantissa_bits_crop) is
		begin
			if (n <= 11) then
				if (characteristic <= characteristic_underflow_bound(n)) then
					round_down_underflows <= '1';
				else
					round_down_underflows <= '0';
				end if;

				if (characteristic >= characteristic_overflow_bound(n)) then
					round_up_overflows <= '1';
				else
					round_up_overflows <= '0';
				end if;
			else
				if (mantissa_bits_crop = mantissa_bits_crop_zero) then
					if (characteristic = -255) then
						round_down_underflows <= '1';
					else
						round_down_underflows <= '0';
					end if;
				else
					round_down_underflows <= '0';
				end if;

				if (mantissa_bits_crop = mantissa_bits_crop_one) then
					if (characteristic = 254) then
						round_up_overflows <= '1';
					else
						round_up_overflows <= '0';
					end if;
				else
					round_up_overflows <= '0';
				end if;
			end if;
		end process check_characteristic;

	end block predict_underflow_overflow;

	determine_characteristic_precursor : block is
		signal characteristic_bits   : std_ulogic_vector(8 downto 0);
		signal characteristic_normal : std_ulogic_vector(7 downto 0);
	begin
		characteristic_bits      <= std_ulogic_vector(to_signed(characteristic, 9));
		characteristic_normal    <= characteristic_bits(7 downto 0) when direction_bit = '1' else
	                            not characteristic_bits(7 downto 0);
		characteristic_precursor <= std_ulogic_vector(to_unsigned(to_integer(unsigned(characteristic_normal)) + 1, 8));
	end block determine_characteristic_precursor;

	detect_leading_one_8 : block is
		signal input              : std_ulogic_vector(7 downto 0);
		signal leading_one_offset : natural range 0 to 7;
		signal lod4_low           : natural range 0 to 3;
		signal lod4_high          : natural range 0 to 3;

		type lod4_lut_type is array (0 to 15) of natural range 0 to 3;

		constant lod4_lut : lod4_lut_type :=
		(
		  0, -- 0000
		  0, -- 0001
		  1, -- 0010
		  1, -- 0011
		  2, -- 0100
		  2, -- 0101
		  2, -- 0110
		  2, -- 0111
		  3, -- 1000
		  3, -- 1001
		  3, -- 1010
		  3, -- 1011
		  3, -- 1100
		  3, -- 1101
		  3, -- 1110
		  3  -- 1111
		);
	begin
		input <= characteristic_precursor;

		lod4_low           <= lod4_lut(to_integer(unsigned(input(3 downto 0))));
		lod4_high          <= lod4_lut(to_integer(unsigned(input(7 downto 4))));
		leading_one_offset <= lod4_low when input(7 downto 4) = "0000" else
	                      to_integer(unsigned('1' & std_ulogic_vector(to_unsigned(lod4_high, 2))));

		regime <= leading_one_offset;
	end block detect_leading_one_8;

	generate_extended_takum : block is
		signal regime_bits                  : std_ulogic_vector(2 downto 0);
		signal characteristic_bits          : std_ulogic_vector(6 downto 0);
		signal characteristic_mantissa_bits : std_ulogic_vector(n + 8 downto 0);
	begin

		set_regime_and_characteristic_raw_bits : process (direction_bit, regime, characteristic_precursor) is
		begin
			if (direction_bit = '0') then
				regime_bits         <= not std_ulogic_vector(to_unsigned(regime, 3));
				characteristic_bits <= not characteristic_precursor(6 downto 0);
			else
				regime_bits         <= std_ulogic_vector(to_unsigned(regime, 3));
				characteristic_bits <= characteristic_precursor(6 downto 0);
			end if;
		end process set_regime_and_characteristic_raw_bits;

		characteristic_mantissa_bits <= std_ulogic_vector(shift_right(unsigned(std_ulogic_vector'(characteristic_bits & mantissa_bits & (6 downto 0 => '0'))), regime));
		extended_takum               <= sign_bit & direction_bit & regime_bits & characteristic_mantissa_bits(n + 1 downto 0);
	end block generate_extended_takum;

	round : block is
		signal takum_rounded_up   : std_ulogic_vector(n - 1 downto 0);
		signal takum_rounded_down : std_ulogic_vector(n - 1 downto 0);
		signal is_rest_zero       : std_ulogic;
	begin
		takum_rounded_up   <= std_ulogic_vector(to_unsigned(to_integer(unsigned(extended_takum(n + 6 downto 7))) + 1, n));
		takum_rounded_down <= extended_takum(n + 6 downto 7);
		is_rest_zero       <= '1' when extended_takum(5 downto 0) = "000000" else
	                      '0';

		takum_rounded <= takum_rounded_up when ((round_down_underflows = '1') or (round_up_overflows = '0' and extended_takum(6) = '1' and (is_rest_zero = '0' or extended_takum(7) = '1'))) else
	                 takum_rounded_down;
	end block round;

	drive_output : process (is_zero, is_nar, takum_rounded) is
	begin
		if (is_zero = '1' or is_nar = '1') then
			takum <= (n - 1 => is_nar, others => '0');
		else
			takum <= takum_rounded;
		end if;
	end process drive_output;

end architecture rtl;
