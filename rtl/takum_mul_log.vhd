-- ============================================================================
-- takum_mul_log.vhd
-- Multiplier for logarithmic takum, working on the internal representation
-- (sign, lbar) that the official codec produces and consumes.
--
-- Why this is only an adder
-- -------------------------
-- A logarithmic takum word stands for
--
--     x = (-1)^S * sqrt(e)^l
--
-- so the product of two of them is
--
--     x_a * x_b = (-1)^(S_a xor S_b) * sqrt(e)^(l_a + l_b)
--
-- Powers of the same base multiply by adding exponents, so there is nothing to
-- multiply: one xor for the sign, one addition for the magnitude.
--
-- The crossed signs
-- -----------------
-- The codec does not expose l but the *barred* value lbar = (-1)^S * l, which
-- saves a two's complement negation in the decoder and in the encoder.  Undoing
-- the bar on both operands and re-applying it to the result,
--
--     lbar_y = (-1)^S_y * (l_a + l_b),  with S_y = S_a xor S_b
--
-- and since (-1)^(S_a xor S_b) = (-1)^S_a * (-1)^S_b, each term keeps the sign
-- of the *other* operand:
--
--     lbar_y = (-1)^(S_b) * lbar_a + (-1)^(S_a) * lbar_b
--
-- In hardware: two conditional negators in parallel, then one adder.
--
-- Format and range
-- ----------------
-- lbar is fixed point Q9.F with F = N - 5, so it is N + 4 bits wide and lives in
-- (-255, 255).  The sum therefore lives in (-510, 510) and needs exactly one
-- extra integer bit.  The sum is exact: both operands share the same F, so no
-- rounding happens here - the encoder does all the rounding.
--
-- Out-of-range results saturate rather than overflow, which is the takum rule:
-- a value too large or too small never becomes infinity or zero.
--
-- Special cases: NaR wins over everything; 0 * x = 0 unless x is NaR.
-- Purely combinational.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity takum_mul_log is
  generic (
    N : natural := 16                                  -- takum width
  );
  port (
    a_sign : in  std_logic;
    a_lbar : in  std_logic_vector(N+3 downto 0);       -- Q9.(N-5), two's complement
    a_zero : in  std_logic;
    a_nar  : in  std_logic;

    b_sign : in  std_logic;
    b_lbar : in  std_logic_vector(N+3 downto 0);
    b_zero : in  std_logic;
    b_nar  : in  std_logic;

    y_sign : out std_logic;
    y_lbar : out std_logic_vector(N+3 downto 0);
    y_zero : out std_logic;
    y_nar  : out std_logic
  );
end entity;

architecture rtl of takum_mul_log is
  constant W : natural := N + 4;    -- width of lbar
  constant F : natural := N - 5;    -- fractional bits of lbar

  -- Saturation limits, expressed in Q9.F.  Built by shifting rather than as a
  -- plain integer, because 255 * 2**F overflows the integer type for large N.
  constant L_MAX : signed(W downto 0) :=
    shift_left(to_signed(255, W+1), F) - 1;            -- just under +255
  constant L_MIN : signed(W downto 0) :=
    -shift_left(to_signed(255, W+1), F);               -- exactly -255
begin
  assert N >= 5
    report "takum_mul_log: N must be >= 5 (the IR has F = N-5 fractional bits)"
    severity failure;

  process (all)
    variable a, b, s : signed(W downto 0);   -- one bit wider: Q10.F
    variable nar, zero : std_logic;
  begin
    a := resize(signed(a_lbar), W+1);
    b := resize(signed(b_lbar), W+1);

    -- The crossed signs: each operand is negated by the sign of the other one.
    if b_sign = '1' then a := -a; end if;
    if a_sign = '1' then b := -b; end if;

    s := a + b;

    -- Clamp into the representable range.  No need to look at the sign: the
    -- range of lbar is the same for S = 0 and S = 1, which is one of the small
    -- benefits of the barred representation.
    if s > L_MAX then
      s := L_MAX;
    elsif s < L_MIN then
      s := L_MIN;
    end if;

    nar  := a_nar or b_nar;
    zero := (a_zero or b_zero) and not nar;

    y_nar  <= nar;
    y_zero <= zero;
    if (nar or zero) = '1' then
      y_sign <= '0';                       -- keep the output clean in these cases
      y_lbar <= (others => '0');
    else
      y_sign <= a_sign xor b_sign;
      y_lbar <= std_logic_vector(resize(s, W));
    end if;
  end process;
end architecture;
