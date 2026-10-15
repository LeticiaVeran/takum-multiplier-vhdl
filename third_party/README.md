# third_party

`Takum-Codec-RTL/` is a verbatim copy of
[takum-arithmetic/Takum-Codec-RTL](https://github.com/takum-arithmetic/Takum-Codec-RTL),
tag **v1.1.0** (commit `76e675c`), by Laslo Hunhold, under the ISC licence
(`Takum-Codec-RTL/LICENSE`). Cite it as DOI
[10.5281/zenodo.16923066](https://doi.org/10.5281/zenodo.16923066).

Nothing here is compiled. It is kept as the reference against which the
patched copy in `rtl/codec/` can be compared, and to carry the original licence.

Copied: `rtl/decoder/`, `rtl/encoder/`, `README.md`, `LICENSE`.

Left out:

- `rtl/third_party/` — FloPoCo posit codecs, GPLv3. They are the posit
  baselines used in the codec paper, and they are useful for a takum vs posit
  comparison, but GPLv3 code cannot be redistributed inside an ISC repository.
  Take them from the upstream repository if you need them.
- `simulation/` — the upstream testbenches; this repository has its own in
  `verification/`.

The codec's own README mentions those two folders; they are simply not part of
this copy.
