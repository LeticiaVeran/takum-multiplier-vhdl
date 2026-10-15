-- ============================================================================
-- tb_takum_mul_wave.vhd
-- Waveform testbench for the full multiplier at N = 8, made for Vivado.
--
-- Unlike the testbenches in verification/, this one needs no input files: the
-- vectors are written below and the expected results are computed by a small
-- reference model inside the testbench. Add it to a Vivado project, run the
-- behavioural simulation, and read the result in the Tcl console and in the
-- waveform.
--
-- It runs in two phases, visible in the signal `phase`:
--
--   DEMO   15 hand-picked cases, 20 ns each, chosen to be read in the
--          waveform: 1 x 1, signs, inverses, rounding, a tie, saturation,
--          zero and NaR. The signal `what` names the case on screen.
--   SWEEP  every one of the 2^8 x 2^8 = 65,536 possible pairs, 2 ns each,
--          checked against the reference model.
--
-- The last lines in the console are the verdict:
--   DEMO: 15 vectors, 0 errors
--   SWEEP: 65536 pairs, 0 errors
--   RESULT: PASS
--
-- Signals worth watching (vivado/sim/wave.tcl adds them in this order):
--   a, b, y         the takum words, in binary
--   y_expected      what y should be
--   a_value ...     the same words as real numbers, so you can read 3.08 * 3.08
--   exact_product   a_value * b_value, before any rounding
--   rel_error       (y_value - exact_product) / exact_product
--   match, errors   '1' while y = y_expected; running count of mismatches
--
-- The reference model works from the definition of the format:
--   x = (-1)^S * sqrt(e)^l,   so   x_a * x_b = (-1)^(S_a xor S_b) * sqrt(e)^(l_a + l_b)
-- It computes l_y = l_a + l_b exactly (in integer units of 2^-7) and picks the
-- representable word whose value is nearest in the log domain, ties to the
-- even bit pattern. It does not use the crossed-sign rule of the hardware, so a
-- wrong derivation there would show up here as a mismatch.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_takum_mul_wave is
end entity;

architecture sim of tb_takum_mul_wave is

  constant N       : natural := 8;       -- the reference model below assumes 8
  constant T_DEMO  : time    := 20 ns;   -- slow, so each case can be read
  constant T_SWEEP : time    := 2 ns;    -- fast, 65,536 pairs in 131 us

  subtype word_t is std_ulogic_vector(N - 1 downto 0);
  constant ZERO_WORD : word_t := "00000000";
  constant NAR_WORD  : word_t := "10000000";

  -- -------------------------------------------------------------------------
  -- What the waveform is showing. Enumerations appear by name in the waveform.
  -- -------------------------------------------------------------------------
  type phase_t is (START, DEMO, SWEEP, DONE);

  type case_t is (NONE,
                  ONE_TIMES_ONE,   -- 1 x 1 = 1
                  TIMES_ONE,       -- 1 x 3.08 = 3.08
                  POS_TIMES_POS,   -- 2.12 x 2.12 = 4.48, exact
                  POS_TIMES_NEG,   -- 0.47 x -2.12 = -1: sign is a xor
                  NEG_TIMES_NEG,   -- -3.96 x -0.25 = 1
                  INVERSES,        -- 2.12 x 0.47 = 1: the logarithms cancel
                  ROUNDED,         -- 1.06 x 9.49 = 10.10, rounds to 9.49
                  TIE_TO_EVEN,     -- 2.12 x 3.08 = 6.52, exactly between two words
                  SATURATE_HIGH,   -- max x max stays max, never infinity
                  SATURATE_LOW,    -- min x min stays min, never zero
                  MAX_TIMES_MIN,   -- 7.9e51 x 1.26e-52 = 1
                  SATURATE_NEG,    -- -max x max stays -max
                  ZERO_TIMES_X,    -- 0 x 3.08 = 0
                  NAR_TIMES_X,     -- NaR x 3.08 = NaR
                  NAR_TIMES_ZERO,  -- NaR x 0 = NaR: NaR wins over zero
                  EXHAUSTIVE);     -- the sweep over all pairs

  -- -------------------------------------------------------------------------
  -- The demo cases. Expected results come from verification/takum_model.py,
  -- which is independent of both the hardware and the model below.
  -- -------------------------------------------------------------------------
  type demo_t is record
    what    : case_t;
    a, b, y : word_t;
  end record;
  type demo_list_t is array (natural range <>) of demo_t;

  constant DEMO_LIST : demo_list_t := (
    --  case            a           b           expected y
    (ONE_TIMES_ONE,  "01000000", "01000000", "01000000"),  -- 1        x 1         = 1
    (TIMES_ONE,      "01000000", "01001101", "01001101"),  -- 1        x 3.080     = 3.080
    (POS_TIMES_POS,  "01001010", "01001010", "01010000"),  -- 2.117    x 2.117     = 4.482
    (POS_TIMES_NEG,  "00110110", "10110110", "11000000"),  -- 0.4724   x -2.117    = -1
    (NEG_TIMES_NEG,  "10110001", "11001111", "01000000"),  -- -3.955   x -0.2528   = 1
    (INVERSES,       "01001010", "00110110", "01000000"),  -- 2.117    x 0.4724    = 1
    (ROUNDED,        "01000001", "01010011", "01010011"),  -- 1.064    x 9.488     -> 9.488
    (TIE_TO_EVEN,    "01001010", "01001101", "01010010"),  -- 2.117    x 3.080     -> 7.389
    (SATURATE_HIGH,  "01111111", "01111111", "01111111"),  -- 7.91e51  x 7.91e51   -> 7.91e51
    (SATURATE_LOW,   "00000001", "00000001", "00000001"),  -- 1.26e-52 x 1.26e-52  -> 1.26e-52
    (MAX_TIMES_MIN,  "01111111", "00000001", "01000000"),  -- 7.91e51  x 1.26e-52  = 1
    (SATURATE_NEG,   "10000001", "01111111", "10000001"),  -- -7.91e51 x 7.91e51   -> -7.91e51
    (ZERO_TIMES_X,   "00000000", "01001101", "00000000"),  -- 0        x 3.080     = 0
    (NAR_TIMES_X,    "10000000", "01001101", "10000000"),  -- NaR      x 3.080     = NaR
    (NAR_TIMES_ZERO, "10000000", "00000000", "10000000")   -- NaR      x 0         = NaR
  );

  -- -------------------------------------------------------------------------
  -- Reference model, straight from the format definition
  -- -------------------------------------------------------------------------
  -- An 8-bit takum is read as a 12-bit one padded with four zeros ("ghost
  -- bits"), so its logarithm has at most 12 - 5 = 7 fractional bits. Counting
  -- in units of 2^-7 keeps every value an exact integer.
  constant FRAC  : natural := 7;
  constant SCALE : integer := 2**FRAC;

  function is_zero (w : word_t) return boolean is
  begin
    return w = ZERO_WORD;
  end function;

  function is_nar (w : word_t) return boolean is
  begin
    return w = NAR_WORD;
  end function;

  -- lbar = c + m, the barred logarithmic value, in units of 2^-7.
  --   S | D | R R R | C...C (r bits) | M...M (p bits)
  function decode_lbar (w : word_t) return integer is
    variable bits      : std_ulogic_vector(11 downto 0);
    variable r, uc, c  : integer;
    variable p, um     : integer;
  begin
    bits := w & "0000";                                 -- the ghost bits
    if bits(10) = '1' then                              -- direction bit D
      r := to_integer(unsigned(bits(9 downto 7)));      -- regime = R
    else
      r := 7 - to_integer(unsigned(bits(9 downto 7)));  -- regime = 7 - R
    end if;

    uc := 0;                                            -- characteristic bits
    if r > 0 then
      uc := to_integer(unsigned(bits(6 downto 7 - r)));
    end if;
    if bits(10) = '1' then
      c := 2**r - 1 + uc;
    else
      c := -(2**(r + 1)) + 1 + uc;
    end if;

    p  := 7 - r;                                        -- mantissa bits left
    um := 0;
    if p > 0 then
      um := to_integer(unsigned(bits(p - 1 downto 0)));
    end if;
    return c * SCALE + um * 2**(FRAC - p);              -- (c + um / 2^p) * 2^7
  end function;

  -- All 256 values decoded once, at elaboration. Zero and NaR get a
  -- meaningless entry that is never read.
  type lbar_table_t is array (0 to 2**N - 1) of integer;

  function build_lbar_table return lbar_table_t is
    variable t : lbar_table_t;
  begin
    for i in t'range loop
      t(i) := decode_lbar(std_ulogic_vector(to_unsigned(i, N)));
    end loop;
    return t;
  end function;

  constant LBAR : lbar_table_t := build_lbar_table;

  -- The true logarithm l = (-1)^S * lbar.
  function log_value (w : word_t) return integer is
  begin
    if w(N - 1) = '1' then
      return -LBAR(to_integer(unsigned(w)));
    else
      return LBAR(to_integer(unsigned(w)));
    end if;
  end function;

  -- The word a real-number product should round to.
  function reference_product (wa, wb : word_t) return word_t is
    variable sy     : std_ulogic;
    variable ly     : integer;      -- l of the exact product
    variable lbar_y : integer;      -- the same, barred with the result sign
    variable d      : integer;
    variable best_d : integer := integer'high;
    variable best   : word_t  := ZERO_WORD;
    variable w      : word_t;
  begin
    if is_nar(wa) or is_nar(wb) then                    -- NaR wins
      return NAR_WORD;
    elsif is_zero(wa) or is_zero(wb) then               -- then zero
      return ZERO_WORD;
    end if;

    sy := wa(N - 1) xor wb(N - 1);
    ly := log_value(wa) + log_value(wb);                -- exponents add
    if sy = '1' then
      lbar_y := -ly;
    else
      lbar_y := ly;
    end if;

    -- Nearest word of the right sign, measured on lbar. Zero and NaR are not
    -- candidates, which is exactly why results saturate instead of
    -- overflowing to NaR or underflowing to zero.
    for i in 0 to 2**N - 1 loop
      w := std_ulogic_vector(to_unsigned(i, N));
      if w(N - 1) = sy and not is_zero(w) and not is_nar(w) then
        d := abs(LBAR(i) - lbar_y);
        if d < best_d or (d = best_d and w(0) = '0') then   -- ties to even
          best_d := d;
          best   := w;
        end if;
      end if;
    end loop;
    return best;
  end function;

  -- A takum word as a real number, for display. Zero and NaR show as 0.0
  -- (the bit pattern tells them apart), and so does an undefined word, which
  -- is what y is for a moment at time 0, before the chain has settled.
  function to_real (w : word_t) return real is
    variable l : real;
  begin
    if is_x(w) or is_zero(w) or is_nar(w) then
      return 0.0;
    end if;
    l := real(log_value(w)) / real(SCALE);
    if w(N - 1) = '1' then
      return -exp(l / 2.0);                             -- sqrt(e)^l = e^(l/2)
    else
      return exp(l / 2.0);
    end if;
  end function;

  function relative_error (approx, exact : real) return real is
  begin
    if exact = 0.0 then
      return 0.0;
    end if;
    return (approx - exact) / exact;
  end function;

  -- A word as text, for the console ('image of '1' is "'1'", hence the (2)).
  function bits (w : word_t) return string is
    variable s : string(1 to N);
  begin
    for i in w'range loop
      s(N - i) := std_ulogic'image(w(i))(2);
    end loop;
    return s;
  end function;

  -- -------------------------------------------------------------------------
  -- Signals shown in the waveform
  -- -------------------------------------------------------------------------
  signal phase         : phase_t := START;
  signal what          : case_t  := NONE;
  signal index         : natural := 0;

  signal a, b          : word_t  := ZERO_WORD;
  signal y             : word_t;
  signal y_expected    : word_t  := ZERO_WORD;

  signal a_value       : real    := 0.0;
  signal b_value       : real    := 0.0;
  signal y_value       : real    := 0.0;
  signal exact_product : real    := 0.0;
  signal rel_error     : real    := 0.0;

  signal match         : std_ulogic := '1';
  signal errors        : natural    := 0;

begin

  assert N = 8
    report "tb_takum_mul_wave: the reference model is written for N = 8"
    severity failure;

  -- The design under test: takum -> decoder -> multiplier -> encoder -> takum
  dut : entity work.takum_mul_top(rtl)
    generic map (N => N)
    port map (a_takum => a, b_takum => b, y_takum => y);

  -- Real-number views, recomputed whenever a word changes
  a_value       <= to_real(a);
  b_value       <= to_real(b);
  y_value       <= to_real(y);
  exact_product <= a_value * b_value;
  rel_error     <= relative_error(y_value, exact_product);

  stimulus : process
    variable demo_errors  : natural := 0;
    variable sweep_errors : natural := 0;
    variable total        : natural := 0;
    variable expected     : word_t;

    -- Apply one pair, wait half a period for the chain to settle, compare,
    -- then hold the inputs for the other half so the result stays visible.
    procedure apply (wa, wb, wy : word_t; period : time; ok : out boolean) is
    begin
      a          <= wa;
      b          <= wb;
      y_expected <= wy;
      wait for period / 2;
      ok := (y = wy);
      if ok then
        match <= '1';
      else
        match  <= '0';
        total  := total + 1;
        errors <= total;
      end if;
      wait for period / 2;
    end procedure;

    variable ok : boolean;
  begin
    -- ---- phase 1: the readable cases -------------------------------------
    phase <= DEMO;
    for i in DEMO_LIST'range loop
      what  <= DEMO_LIST(i).what;
      index <= i + 1;
      apply(DEMO_LIST(i).a, DEMO_LIST(i).b, DEMO_LIST(i).y, T_DEMO, ok);
      report "DEMO " & integer'image(i + 1) & "  " & case_t'image(DEMO_LIST(i).what) &
             "  a=" & bits(DEMO_LIST(i).a) & " b=" & bits(DEMO_LIST(i).b) &
             "  y=" & bits(y) & "  expected=" & bits(DEMO_LIST(i).y) &
             "  " & real'image(to_real(DEMO_LIST(i).a)) &
             " * " & real'image(to_real(DEMO_LIST(i).b)) &
             " -> " & real'image(to_real(y));
      if not ok then
        demo_errors := demo_errors + 1;
        report "MISMATCH in demo case " & case_t'image(DEMO_LIST(i).what) severity error;
      end if;
    end loop;
    report "DEMO: " & integer'image(DEMO_LIST'length) & " vectors, " &
           integer'image(demo_errors) & " errors";

    -- ---- phase 2: every possible pair --------------------------------------
    phase <= SWEEP;
    what  <= EXHAUSTIVE;
    for i in 0 to 2**N - 1 loop
      for j in 0 to 2**N - 1 loop
        index    <= i * 2**N + j;
        expected := reference_product(std_ulogic_vector(to_unsigned(i, N)),
                                      std_ulogic_vector(to_unsigned(j, N)));
        apply(std_ulogic_vector(to_unsigned(i, N)),
              std_ulogic_vector(to_unsigned(j, N)), expected, T_SWEEP, ok);
        if not ok then
          sweep_errors := sweep_errors + 1;
          if sweep_errors <= 10 then                    -- only the first few
            report "MISMATCH a=" & bits(std_ulogic_vector(to_unsigned(i, N))) &
                   " b=" & bits(std_ulogic_vector(to_unsigned(j, N))) &
                   " y=" & bits(y) & " expected=" & bits(expected) severity error;
          end if;
        end if;
      end loop;
    end loop;
    report "SWEEP: " & integer'image(2**(2 * N)) & " pairs, " &
           integer'image(sweep_errors) & " errors";

    -- ---- verdict ----------------------------------------------------------
    phase <= DONE;
    what  <= NONE;
    if demo_errors + sweep_errors = 0 then
      report "RESULT: PASS";
    else
      report "RESULT: FAIL" severity error;
    end if;
    wait;                                               -- no clock: simulation ends here
  end process;

end architecture;
