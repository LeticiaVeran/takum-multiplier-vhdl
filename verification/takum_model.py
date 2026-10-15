#!/usr/bin/env python3
"""Reference model and stimulus generator for the logarithmic takum multiplier.

Everything the testbenches need, in one file.  A testbench on its own can only
apply inputs and look at outputs; something independent has to say what the
right answer is.  That is this file.  It never mirrors the hardware: it works
from the definition of the format, with exact fractions, so an error in the
hardware and an error here are unlikely to cancel out.

The format, in one picture (N = 16):

    S | D | R R R | C ... C | M ... M
    1   1     3       r        p = N - r - 5

    S  sign of the number
    D  direction bit: 1 when the characteristic is >= 0
    R  three regime bits, saying how many characteristic bits follow
    C  characteristic: the integer part of the logarithm (-255..254)
    M  mantissa: the fractional part of the logarithm, in [0, 1)

A takum word stands for  x = (-1)^S * sqrt(e)^l,  so multiplying means adding
exponents.  The codec exposes the *barred* value lbar = (-1)^S * l = c + m, as
fixed point Q9.(N-5), which leaves the multiplier rule with crossed signs:

    S_y    = S_a xor S_b
    lbar_y = (-1)^(S_b) * lbar_a + (-1)^(S_a) * lbar_b    saturated to [-255, 255)

Commands
--------
    python3 takum_model.py mul-vectors    N [count]  -> vec_mul_N.txt
    python3 takum_model.py demo-vectors   N          -> vec_mul_N.txt (9 readable cases)
    python3 takum_model.py decode-vectors N          -> dec_N.txt
    python3 takum_model.py pairs          N [count]  -> pairs_N.txt + exp_N.txt
    python3 takum_model.py pairs-random   N [count]  -> pairs_N.txt
    python3 takum_model.py check          N          compares out_N.txt with exp_N.txt
    python3 takum_model.py check-local    N          compares out_N.txt by local rounding

`pairs` and `check` enumerate 2^N words, so they are practical up to about
N = 20.  Beyond that use `pairs-random` and `check-local`.
"""

from bisect import bisect_left
from fractions import Fraction as F
import math
import random
import sys


# ===========================================================================
# The format itself
# ===========================================================================

def decode(bits, n):
    """Decode one takum word straight from the definition.

    Returns 'zero', 'NaR', or (sign, lbar) with lbar an exact fraction.
    """
    if n < 12:
        # "Ghost bits": a short takum behaves like a 12-bit one padded with zeros.
        bits = bits.ljust(12, '0')
        n = 12

    S = int(bits[0])
    if set(bits[1:]) == {'0'}:            # everything after the sign is zero
        return 'NaR' if S else 'zero'

    D = int(bits[1])                      # direction bit
    R = bits[2:5]                         # three regime bits
    r = int(R, 2) if D else 7 - int(R, 2)  # characteristic length

    uC = int(bits[5:5 + r], 2) if r else 0
    c = (2**r - 1 + uC) if D else (-2**(r + 1) + 1 + uC)

    p = n - r - 5                         # mantissa bits actually present
    uM = int(bits[5 + r:5 + r + p], 2) if p else 0

    return (S, F(c) + F(uM, 2**p))        # lbar = characteristic + mantissa


def multiply(Sa, la, Sb, lb):
    """The rule under test, on exact values: sign xor, crossed-sign sum, clamp.

    Here lbar is a real value (a fraction), so the limits are plain +-255.
    """
    S = Sa ^ Sb
    l = (-1)**Sb * la + (-1)**Sa * lb
    return S, max(F(-255), min(F(255), l))   # takum saturates, never overflows


def multiply_scaled(Sa, la, Sb, lb, F_bits):
    """Same rule, but on lbar as an integer in Q9.F, which is how the hardware
    and the test vectors carry it.  The limits are scaled by 2^F as well."""
    hi, lo = _lbar_limits(F_bits)
    S = Sa ^ Sb
    l = (-1)**Sb * la + (-1)**Sa * lb
    return S, max(lo, min(hi, l))


# ===========================================================================
# Vectors for the stand-alone multiplier (internal representation)
# ===========================================================================

def _lbar_limits(F_bits):
    """Largest and smallest lbar as integers in Q9.F."""
    return 255 * 2**F_bits - 1, -255 * 2**F_bits


def _to_real(S, lbar_int, F_bits):
    """(sign, lbar) -> real number, for the independent float cross-check."""
    l = (-1)**S * lbar_int / 2**F_bits
    return (-1)**S * math.exp(l / 2)          # sqrt(e)^l == e^(l/2)


def _ir_line(Sa, la, za, na, Sb, lb, zb, nb, S, l, zero, nar, W):
    """One testbench line, every field in binary."""
    mask = (1 << W) - 1                        # print negatives in two's complement
    return (f"{Sa} {la & mask:0{W}b} {za} {na} "
            f"{Sb} {lb & mask:0{W}b} {zb} {nb} "
            f"{S} {l & mask:0{W}b} {zero} {nar}\n")


def mul_vectors(n, count):
    """Write vec_mul_<n>.txt: corner cases, random cases and special values."""
    F_bits, W = n - 5, n + 4
    hi, lo = _lbar_limits(F_bits)
    rnd = random.Random(1234)                  # fixed seed: reproducible runs
    cases = []

    edges = [lo, lo + 1, -1, 0, 1, hi - 1, hi, hi // 2, lo // 2, 2**F_bits, -2**F_bits]
    for la in edges:
        for lb in edges:
            for Sa in (0, 1):
                for Sb in (0, 1):
                    cases.append((Sa, la, 0, 0, Sb, lb, 0, 0))

    for _ in range(count):
        cases.append((rnd.randint(0, 1), rnd.randint(lo, hi), 0, 0,
                      rnd.randint(0, 1), rnd.randint(lo, hi), 0, 0))

    for za, na, zb, nb in [(1, 0, 0, 0), (0, 0, 1, 0), (1, 0, 1, 0), (0, 1, 0, 0),
                           (0, 0, 0, 1), (1, 0, 0, 1), (0, 1, 1, 0), (0, 1, 0, 1)]:
        cases.append((0, 0, za, na, 1, 1000 % hi, zb, nb))

    mismatches = 0
    with open(f"vec_mul_{n}.txt", "w") as f:
        for Sa, la, za, na, Sb, lb, zb, nb in cases:
            nar = na | nb                      # NaR wins over everything
            zero = (za | zb) & (1 - nar)       # 0 * x = 0, unless x is NaR
            if nar or zero:
                S, l = 0, 0
            else:
                S, l = multiply_scaled(Sa, la, Sb, lb, F_bits)

                # Independent cross-check: rebuild both reals, multiply them as
                # floats, go back to the log domain.  This does not use the
                # crossed-sign rule, so a wrong derivation would show up here.
                product = _to_real(Sa, la, F_bits) * _to_real(Sb, lb, F_bits)
                S_ref = 1 if product < 0 else 0
                l_ref = round((-1)**S_ref * 2 * math.log(abs(product)) * 2**F_bits)
                l_ref = max(lo, min(hi, l_ref))
                # A double has 53 mantissa bits, so for wide takums it cannot
                # resolve every fractional bit; widen the tolerance accordingly.
                if S_ref != S or abs(l_ref - l) > max(1, 2**(F_bits - 40)):
                    mismatches += 1

            f.write(_ir_line(Sa, la, za, na, Sb, lb, zb, nb, S, l, zero, nar, W))

    print(f"N={n}: {len(cases)} vectors, formula vs reals mismatches = {mismatches}")
    return mismatches


def demo_vectors(n):
    """Write nine readable vectors and print a table of what each one is.

    mul-vectors writes 20 000 vectors full of values like -522240, which is
    correct but unreadable in a waveform.  These nine were chosen for meaning.
    """
    F_bits, W = n - 5, n + 4
    hi, lo = _lbar_limits(F_bits)

    def to_ir(x):
        S = 1 if x < 0 else 0
        return S, round((-1)**S * 2 * math.log(abs(x)) * 2**F_bits)

    cases = []
    for xa, xb, note in [
        (3.0,   5.0,  "3 x 5 = 15 (positive x positive)"),
        (0.5,  -2.0,  "0.5 x -2 = -1 (opposite signs)"),
        (-4.0, -0.25, "-4 x -0.25 = 1 (negative x negative)"),
        (1.0,   7.0,  "1 x 7 = 7 (multiplying by 1 changes nothing)"),
        (2.0,   0.5,  "2 x 0.5 = 1 (inverses: the lbars cancel out)"),
    ]:
        Sa, la = to_ir(xa)
        Sb, lb = to_ir(xb)
        cases.append((Sa, la, 0, 0, Sb, lb, 0, 0, note))

    cases.append((0, hi, 0, 0, 0, hi, 0, 0, "huge x huge -> saturates high"))
    cases.append((0, lo, 0, 0, 0, lo, 0, 0, "tiny x tiny -> saturates low"))
    Sa, la = to_ir(3.0)
    cases.append((0, 0, 1, 0, Sa, la, 0, 0, "0 x 3 = 0"))
    cases.append((0, 0, 0, 1, Sa, la, 0, 0, "NaR x 3 = NaR"))

    print(f"N={n}  F={F_bits} fractional bits  (real lbar = integer / {2**F_bits})\n")
    print(f"{'t(ns)':>5} | {'a':>12} | {'b':>12} | {'expected y':>12} | case")
    print("-" * 95)

    with open(f"vec_mul_{n}.txt", "w") as f:
        for i, (Sa, la, za, na, Sb, lb, zb, nb, note) in enumerate(cases):
            nar = na | nb
            zero = (za | zb) & (1 - nar)
            if nar or zero:
                S, l = 0, 0
                y_text = "NaR" if nar else "0"
            else:
                S, l = multiply_scaled(Sa, la, Sb, lb, F_bits)
                y_text = f"{_to_real(S, l, F_bits):.6g}"

            a_text = "NaR" if na else ("0" if za else f"{_to_real(Sa, la, F_bits):.6g}")
            b_text = "NaR" if nb else ("0" if zb else f"{_to_real(Sb, lb, F_bits):.6g}")
            print(f"{i+1:>5} | {a_text:>12} | {b_text:>12} | {y_text:>12} | {note}")
            f.write(_ir_line(Sa, la, za, na, Sb, lb, zb, nb, S, l, zero, nar, W))

    print(f"\n{len(cases)} vectors written to vec_mul_{n}.txt")
    return 0


# ===========================================================================
# Vectors for the decoder
# ===========================================================================

def decode_vectors(n):
    """Write dec_<n>.txt: the expected decoder output for every N-bit word."""
    p_max = n - 5
    with open(f"dec_{n}.txt", "w") as f:
        for i in range(2**n):
            bits = format(i, f'0{n}b')
            S = int(bits[0])
            is_zero = 1 if set(bits) == {'0'} else 0
            is_nar = 1 if (S == 1 and set(bits[1:]) == {'0'}) else 0

            padded = bits.ljust(12, '0') if n < 12 else bits
            D = int(padded[1])
            R = padded[2:5]
            r = int(R, 2) if D else 7 - int(R, 2)
            uC = int(padded[5:5 + r], 2) if r else 0
            c = (2**r - 1 + uC) if D else (-2**(r + 1) + 1 + uC)

            p = 0 if r >= p_max else p_max - r      # tapered precision
            mantissa = bits[n - p:] if p else ''
            mantissa_field = (mantissa + '0' * (p_max - p)) if p_max else ''

            # lbar = 9-bit two's complement characteristic, then the mantissa
            f.write(f"{bits} {S} {format(c & 0x1FF, '09b')}{mantissa_field} "
                    f"{p:04b} {is_zero} {is_nar}\n")

    print(f"{2**n} vectors written to dec_{n}.txt")
    return 0


# ===========================================================================
# Stimulus and checking for the full chain
# ===========================================================================

def pairs_exact(n, count):
    """Write pairs_<n>.txt (stimulus) and exp_<n>.txt (expected results).

    Writing the expectations now, instead of recomputing them at check time,
    means the check can never be run against a different set of pairs.
    """
    table = {}
    for i in range(2**n):
        bits = format(i, f'0{n}b')
        d = decode(bits, n)
        if isinstance(d, tuple):
            table[bits] = d

    # Sorted per sign, so the nearest value can be found by binary search
    # instead of scanning all 2^N candidates for every pair.
    by_sign = {0: [], 1: []}
    for bits, (S, l) in table.items():
        by_sign[S].append((l, bits))
    for S in (0, 1):
        by_sign[S].sort()
    keys = {S: [l for l, _ in by_sign[S]] for S in (0, 1)}

    def expected(a, b):
        da, db = decode(a, n), decode(b, n)
        if da == 'NaR' or db == 'NaR':
            return '1' + '0' * (n - 1)
        if da == 'zero' or db == 'zero':
            return '0' * n
        Sy, ly = multiply(da[0], da[1], db[0], db[1])

        # Round to nearest representable value; ties go to the even pattern.
        # The candidates can only be the two values bracketing ly.
        candidates = by_sign[Sy]
        i = bisect_left(keys[Sy], ly)
        best, best_distance = None, None
        for j in (i - 1, i, i + 1):
            if 0 <= j < len(candidates):
                l, bits = candidates[j]
                d = abs(l - ly)
                if (best_distance is None or d < best_distance
                        or (d == best_distance and bits[-1] == '0')):
                    best, best_distance = bits, d
        return best

    if count == 0:                              # every possible pair
        words = [format(i, f'0{n}b') for i in range(2**n)]
        pairs = [(a, b) for a in words for b in words]
    else:
        rnd = random.Random(7)
        pairs = [(format(rnd.randrange(2**n), f'0{n}b'),
                  format(rnd.randrange(2**n), f'0{n}b')) for _ in range(count)]
        pairs += [('0' * n, '0' * n),                  # zero * zero
                  ('1' + '0' * (n - 1), '0' * n)]      # NaR * zero

    with open(f"pairs_{n}.txt", "w") as fp, open(f"exp_{n}.txt", "w") as fe:
        for a, b in pairs:
            fp.write(f"{a} {b}\n")
            fe.write(expected(a, b) + "\n")

    print(f"{len(pairs)} pairs written to pairs_{n}.txt (expectations in exp_{n}.txt)")
    return 0


def pairs_random(n, count):
    """Write pairs_<n>.txt only: stimulus for widths too large to enumerate."""
    rnd = random.Random(99)
    with open(f"pairs_{n}.txt", "w") as f:
        for _ in range(count):
            f.write(f"{rnd.randrange(2**n):0{n}b} {rnd.randrange(2**n):0{n}b}\n")
        f.write(f"{'0' * n} {'0' * n}\n")
        f.write(f"{'1' + '0' * (n - 1)} {'0' * n}\n")
    print(f"{count + 2} pairs written to pairs_{n}.txt")
    return 0


def _missing_outputs(n_pairs, n_outputs):
    """Count stimulus lines the simulation never answered.

    zip() stops at the shorter list, so if the simulation crashed after the
    first vector the comparison loop would see a single line, find it correct
    and report MISMATCHES=0.  Every unanswered pair is therefore counted as a
    mismatch here, so a crashed run can never pass.
    """
    missing = max(0, n_pairs - n_outputs)
    if missing:
        print(f"MISSING OUTPUTS: {n_pairs} pairs applied, only {n_outputs} results "
              f"written - the simulation stopped early")
    return missing


def check_exact(n):
    """Compare out_<n>.txt against the expectations written by pairs_exact."""
    expected = [l.strip() for l in open(f"exp_{n}.txt") if l.strip()]
    hardware = [l.strip() for l in open(f"out_{n}.txt") if l.strip()]
    pairs = [l.split() for l in open(f"pairs_{n}.txt") if l.strip()]

    ok = errors = 0
    for (a, b), e, y in zip(pairs, expected, hardware):
        if y == e:
            ok += 1
        else:
            errors += 1
            if errors <= 5:
                print(f"MISMATCH a={a} b={b} hw={y} expected={e}")
    errors += _missing_outputs(len(pairs), len(hardware))
    print(f"full chain n={n}: OK={ok} MISMATCHES={errors}")
    return errors


def check_local(n):
    """Check out_<n>.txt without enumerating anything.

    The word the hardware produced must be closer to the exact result than its
    two immediate neighbours, and on a tie it must be the even pattern.  That is
    what "round to nearest, ties to even" means, so any rounding error shows up.
    """
    pairs = [l.split() for l in open(f"pairs_{n}.txt") if l.strip()]
    hardware = [l.strip() for l in open(f"out_{n}.txt") if l.strip()]
    ok = errors = 0

    for (a, b), y in zip(pairs, hardware):
        da, db = decode(a, n), decode(b, n)

        if da == 'NaR' or db == 'NaR':
            good = (y == '1' + '0' * (n - 1))
        elif da == 'zero' or db == 'zero':
            good = (y == '0' * n)
        else:
            Sy, ly = multiply(da[0], da[1], db[0], db[1])
            dy = decode(y, n)
            if not isinstance(dy, tuple) or dy[0] != Sy:
                good = False                   # wrong sign, or zero/NaR out of nowhere
            else:
                distance = abs(dy[1] - ly)
                good = True
                for step in (-1, 1):           # the word below and the word above
                    neighbour = format((int(y, 2) + step) % 2**n, f'0{n}b')
                    dn = decode(neighbour, n)
                    if isinstance(dn, tuple) and dn[0] == Sy:
                        d = abs(dn[1] - ly)
                        if d < distance or (d == distance and y[-1] == '1'):
                            good = False       # a neighbour was closer, or evener

        if good:
            ok += 1
        else:
            errors += 1
            if errors <= 5:
                print(f"MISMATCH a={a} b={b} hw={y}")

    errors += _missing_outputs(len(pairs), len(hardware))
    print(f"full chain (local check) n={n}: OK={ok} MISMATCHES={errors}")
    return errors


# ===========================================================================
# Command line
# ===========================================================================

def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2

    command, n = argv[1], int(argv[2])
    count = int(argv[3]) if len(argv) > 3 else None

    if command == "mul-vectors":
        return mul_vectors(n, 20000 if count is None else count)
    if command == "demo-vectors":
        return demo_vectors(n)
    if command == "decode-vectors":
        return decode_vectors(n)
    if command == "pairs":
        return pairs_exact(n, 3000 if count is None else count)
    if command == "pairs-random":
        return pairs_random(n, 3000 if count is None else count)
    # The exit status is 1 on any mismatch, never the mismatch count itself:
    # exit statuses wrap modulo 256, so exactly 256 errors would read as success.
    if command == "check":
        return 1 if check_exact(n) else 0
    if command == "check-local":
        return 1 if check_local(n) else 0

    print(f"unknown command: {command}")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
