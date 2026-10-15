# Bibliography

Annotated reading list for this project. Each entry says what the work
contributes and which part of this repository depends on it. BibTeX entries are
in [`references.bib`](references.bib).

## Primary sources

**L. Hunhold. "Beating Posits at Their Own Game: Takum Arithmetic." CoNGA 2024,
LNCS vol. 14666, Springer, 2024. doi:10.1007/978-3-031-72709-2_1**

Defines the format. Definition 1 gives the bit layout `(S, D, R, C, M)`, the
regime, the characteristic `c ∈ {-255,…,254}`, the mantissa and the logarithmic
value `ℓ = (-1)^S (c + m)`, from which the encoded value `τ = (-1)^S √e^ℓ`
follows. Definition 2 gives the linear variant. The guaranteed `n - 12` fraction
bits and the bounded dynamic range — the two properties that separate takum from
posits — come from here, as does the name: *takmarkað umfang*, Icelandic for
"limited range". Everything in `takum_mul_log.vhd` ultimately derives from these
definitions, and the decoding in `takum_model.py` implements them directly.

**L. Hunhold. "Design and Implementation of a Takum Arithmetic Hardware Codec in
VHDL." arXiv:2408.10594, 2025.**

The source of the codec vendored here, and of the internal representation this
multiplier operates on. Section 3 proposes the *barred logarithmic value*
`ℓ̄ := c + m = (-1)^S ℓ` and the representation `(S, ℓ̄)`, arguing that `ℓ̄` is
monotonic in `m` and therefore removes the two's complement negation that the
canonical `(S, ℓ)` representation needs after decoding and before encoding. It
also states plainly that the cost falls on arithmetic, since multiplication and
division must handle all sign combinations regardless — which is exactly the
crossed-sign rule implemented here. Sections 4 and 5 describe the decoder and
encoder, including the underflow/overflow predictor, the characteristic
precursor, the 8-bit leading-one detector and the rounder. Section 6 reports the
FPGA evaluation: up to 38 % lower latency and up to 50 % fewer LUTs than the
best posit codecs, measured on a Kintex UltraScale+ with Vivado 2024.1.

**L. Hunhold. Takum Codec RTL, version v1.1.0, 2025. doi:10.5281/zenodo.16923066**

The code itself, vendored unchanged in `third_party/Takum-Codec-RTL/` under
the ISC licence. The copy that is compiled, in `rtl/codec/`, differs in five
documented spots, listed in `rtl/codec/README.md`.

## Context: what takum is an alternative to

**J. L. Gustafson and I. Yonemoto. "Beating Floating Point at Its Own Game: Posit
Arithmetic." Supercomputing Frontiers and Innovations 4(2):71–86, 2017.**

Posits: tapered precision via a unary regime, a single NaR, two's complement
ordering. Takum keeps these ideas and replaces the unbounded regime with three
regime bits plus at most seven characteristic bits, which is what bounds the
taper. Useful as the baseline any comparison of this multiplier will be made
against.

**IEEE Std 754-2019, IEEE Standard for Floating-Point Arithmetic.**

The incumbent. Relevant here mainly for the contrast in special values: IEEE 754
spends many bit patterns on two zeros, two infinities and a family of NaNs,
where takum has exactly two special patterns and saturating arithmetic.

## Context: how takum performs numerically

These papers evaluate the *linear* takum variant, not the logarithmic one
implemented here. They matter for arguing that the format is worth building
hardware for, not for the design of the multiplier itself.

**L. Hunhold and J. Quinlan. "Evaluation of Bfloat16, Posit, and Takum
Arithmetics in Sparse Linear Solvers." IEEE ARITH 2025. arXiv:2412.20268**

LU, QR, GMRES with ILU preconditioning and mixed-precision iterative refinement,
over 295 matrices from the SuiteSparse collection. Tapered-precision formats beat
IEEE 754 in every scenario tested; `takum_linear16` outperforms bfloat16
consistently, where `posit16` sometimes does not; `takum_linear8` avoided
overflow entirely in GMRES. The conclusion worth quoting in a defence is that
with takums the choice of precision becomes decoupled from dynamic range
concerns.

**L. Hunhold and J. Gustafson. "Spectral Methods via FFTs in Emerging Machine
Number Formats: OFP8, Bfloat16, Posit, and Takum Arithmetics." SC '25.
arXiv:2504.21197**

Heat and Poisson equations, round-trip 2D FFT over 900 images, STFT over 2000
audio recordings. Posits lead at low precision with takum close behind; posits
show instability at higher precisions; OFP8 is unusable for this workload. Cite
this one when a balanced account is wanted — takum does not win everywhere.

**L. Hunhold. "Streamlining SIMD ISA Extensions with Takum Arithmetic: A Case
Study on Intel AVX10.2." arXiv:2503.14067, 2025.**

Argues that a single takum format could replace bfloat16, E4M3 and E5M2 in a
vector ISA, collapsing instruction groups. Contains the observation most relevant
to hardware work: all takum precisions share a common decoder that need only
process the 12 most significant bits.

## Comparison targets for synthesis

**R. Murillo et al. "Comparing Different Decodings for Posit Arithmetic." CoNGA
2022, pp. 84–99. doi:10.1007/978-3-031-09779-9_6**

The FloPoCo-2C posit codec, the strongest reference in the codec paper's
evaluation and the natural comparison point once this multiplier is synthesised.

**R. Murillo et al. "Customized Posit Adders and Multipliers Using the FloPoCo
Core Generator." ISCAS 2020. doi:10.1109/ISCAS45731.2020.9180771**

Posit multipliers from the same group: mantissa multiplier, exponent addition,
normalisation, rounding. The six-stage structure that the logarithmic takum
multiplier reduces to four, with no mantissa multiplier at all.

**Y. Uguen et al. "Evaluating the Hardware Cost of the Posit Number System." FPL
2019, pp. 106–113. doi:10.1109/FPL.2019.00026**

Earlier hardware-cost study of posits; useful for area and latency methodology.

## Not used, but worth knowing

**M. K. Jaiswal and H. K.-H. So. "PACoGen: A Hardware Posit Arithmetic Core
Generator." IEEE Access 7:74586–74601, 2019.**

Excluded from the codec paper's comparison as generally inferior to FloPoCo-2C;
listed so the omission is a documented choice rather than an oversight.

**A. Ramachandran et al. "Algorithm-Hardware Co-Design of Distribution-Aware
Logarithmic-Posit Encodings for Efficient DNN Inference." arXiv:2403.05465,
2024.**

Logarithmic posits, which use the canonical `(S, ℓ)` internal representation
rather than the barred one. The direct point of comparison for the design
decision this multiplier inherits.
