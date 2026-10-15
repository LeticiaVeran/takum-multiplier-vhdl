# Synthesis results

Target: Nexys A7-100T, `xc7a100tcsg324-1` (speed grade −1), Vivado 2025.1,
default strategies, out of context, 10 ns clock constraint (see `build.tcl`
and `vivado/README.md`).

Measured with `takum_mul_synth_wrapper`, which registers inputs and outputs,
so the reported path runs from register to register through the design.
Each row is printed by `build.tcl` at the end of a run, ready to paste.

All eight runs were made on 15 October 2026; the full Vivado reports were kept
alongside (not versioned, `reports/` is ignored by git).

## Multiplier alone (`mul`)

| N | Slice LUTs | CARRY4 | DSP | FFs | path delay (ns) | Fmax (MHz) | dynamic power (W) |
|---|---|---|---|---|---|---|---|
| 8 | 34 | 8 | 0 | 45 | 6.960 | 143.7 | 0.001 |
| 16 | 46 | 10 | 0 | 69 | 7.432 | 134.6 | 0.002 |
| 32 | 70 | 14 | 0 | 117 | 7.960 | 125.6 | 0.003 |
| 64 | 118 | 22 | 0 | 213 | 8.699 | 115.0 | 0.005 |

## Full chain (`chain`)

| N | Slice LUTs | CARRY4 | DSP | FFs | path delay (ns) | Fmax (MHz) | dynamic power (W) |
|---|---|---|---|---|---|---|---|
| 8 | 168 | 8 | 0 | 26 | 12.032 | 83.1 | 0.004 |
| 16 | 258 | 14 | 0 | 50 | 12.982 | 77.0 | 0.006 |
| 32 | 433 | 22 | 0 | 116 | 13.950 | 71.7 | 0.011 |
| 64 | 880 | 38 | 0 | 209 | 15.799 | 63.3 | 0.022 |

## How to read these numbers

- **Compare LUTs, not FFs.** The design is combinational; almost every
  flip-flop belongs to the wrapper.
- **Path delay** is `period - WNS`, the time the logic needs; **Fmax** is its
  inverse. Every row is measured with the same 10 ns constraint; a negative
  WNS only means the design needs more than 10 ns (see `vivado/README.md`).
- **DSP** should stay at 0 for the takum multiplier: it is an adder. A posit
  multiplier needs a significand multiplier, which Vivado puts into DSP blocks.
  For a LUT-only comparison, run both with `nodsp`.
- **Dynamic power** is Vivado's vectorless estimate, good for comparing designs
  measured the same way, not an absolute figure.
- For a comparison with posits, the `mul` rows are the counterpart of a posit
  multiplier core; the `chain` rows, of a posit decoder + multiplier + encoder.

## What the numbers show

- **No DSP block in any configuration.** The multiplier is an adder, at every
  width.
- **The multiplier alone is small and grows linearly**: 34 LUTs at 8 bits,
  118 at 64. Its delay grows slowly, from 6.96 to 8.70 ns (+25 % for eight
  times the width), because the adder runs on the fast carry chain (CARRY4).
  It meets the 10 ns constraint at every width.
- **The codec dominates the full unit.** At N = 16 the chain takes 258 LUTs
  and the multiplier 46, so roughly 80 % of the area is the two decoders and
  the encoder; at N = 64, 880 against 118, about 87 %. The difference is
  approximate, since synthesis optimises the chain as a whole.
- **The chain is one long combinational path** (decoder → adder → saturation →
  encoder → rounding), from 12.0 ns at 8 bits to 15.8 ns at 64 bits (+31 %).
  The growth comes from carry chains that get longer with N, the `lbar`
  adder and the rounding increment in the encoder: the worst path at N = 64
  crosses 31 CARRY4 blocks, against 3 at N = 8. A
  pipelined version (registers between decoder, multiplier and encoder) would
  raise the clock rate at the cost of latency.
- **Dynamic power** follows the area: 4 to 22 mW for the chain, 1 to 5 mW for
  the multiplier alone, at 100 MHz, vectorless estimate.

## Critical paths

| Run | Logic levels | CARRY4 in path | Logic / routing |
|---|---|---|---|
| mul, N = 8 | 8 | 4 | 41 % / 59 % |
| mul, N = 16 | 9 | 5 | 45 % / 55 % |
| mul, N = 32 | 12 | 8 | 45 % / 55 % |
| mul, N = 64 | 22 | 18 | 55 % / 45 % |
| chain, N = 8 | 15 | 3 | 30 % / 70 % |
| chain, N = 16 | 19 | 7 | 40 % / 60 % |
| chain, N = 32 | 28 | 16 | 43 % / 57 % |
| chain, N = 64 | 41 | 31 | 49 % / 51 % |
