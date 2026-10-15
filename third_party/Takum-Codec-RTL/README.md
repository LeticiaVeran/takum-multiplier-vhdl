# Takum Codec RTL

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.14540046.svg)](https://doi.org/10.5281/zenodo.14540046)

This repository contains a complete decoder and encoder for both the default logarithmic and linear Takum arithmetic formats, implemented in VHDL. The internal representation used for decoding and encoding closely resembles the representation employed in Posit arithmetic cores, positioning the codec as the primary point of comparison between takums and posits.

In addition to the RTL descriptions in `rtl/`, the repository includes full simulation testbenches for verifying functionality in `simulation/`.

## Authors and Licenses

This project is developed by Laslo Hunhold and licensed under the ISC license, except `rtl/third_party/`. See LICENSE for copyright and license details.

The posit codecs in `rtl/third_party/` are licensed under the GNU GPLv3 and authors are listed in the respective source files.
