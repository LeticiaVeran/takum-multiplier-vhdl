# rtl/codec — the official takum codec, patched

These four files are the logarithmic decoder and encoder of
[Takum-Codec-RTL](https://github.com/takum-arithmetic/Takum-Codec-RTL) v1.1.0
by Laslo Hunhold (ISC licence, see `third_party/Takum-Codec-RTL/LICENSE`).
They are the copies that both flows of this repository compile, in simulation
and in synthesis. The untouched originals live in `third_party/Takum-Codec-RTL/`.

| File | Role |
|---|---|
| `predecoder.vhd` | takum bits → sign, characteristic, mantissa bits, zero/NaR flags |
| `decoder_logarithmic.vhd` | wraps the predecoder and outputs the barred logarithmic value `lbar` |
| `postencoder.vhd` | sign, characteristic, mantissa → takum bits, with rounding |
| `encoder_logarithmic.vhd` | wraps the postencoder and accepts `lbar` |

## What was changed, and why

Five spots differ from the original. Each one is marked in the source with a
`-- PATCH n` comment that quotes the original line and explains the change.

| Patch | File | Original | Problem | Replacement |
|---|---|---|---|---|
| 1, 2 | `predecoder.vhd` | `(n - 1 => '1', others => '0')` | an aggregate may only use `others` next to *locally static* choices; `n - 1` depends on a generic, so the VHDL standard forbids it and GHDL rejects it | `'1' & (n - 2 downto 0 => '0')` |
| 3 | `predecoder.vhd` | `x when n >= 12 else y` | both branches are elaborated, and one has a negative width | `if n >= 12 generate … else generate …` |
| 4 | `postencoder.vhd` | `(n - 1 => is_nar, others => '0')` | same as patch 1 | `is_nar & (n - 2 downto 0 => '0')` |
| 5 | `postencoder.vhd` | `to_unsigned(to_integer(x) + 1, n)` | goes through the VHDL `integer` type, which is 32 bits wide, so it overflows from n = 32 on | `unsigned(x) + 1`, which wraps modulo 2^n exactly as the original truncation did |

Patches 1 to 4 change only the spelling: Vivado happens to accept the original
constructs, and it accepts the patched ones too. Patch 5 changes what tools can
do: without it the chain cannot be simulated at N = 32 or N = 64 in any
simulator with a 32-bit `integer`.

The functional equivalence is not taken on faith: the full chain built from
these files matches the reference model on every one of the 65,536 pairs at
N = 8, and on sampled pairs at N = 12, 16, 24, 32 and 64
(see `verification/`).

To see every difference yourself:

```
diff -r third_party/Takum-Codec-RTL/rtl/decoder rtl/codec
diff -r third_party/Takum-Codec-RTL/rtl/encoder rtl/codec
```

(Each command also lists the files that exist only on one side; ignore those.)
