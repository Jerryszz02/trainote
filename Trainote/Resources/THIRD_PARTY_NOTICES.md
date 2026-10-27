# Third-Party Notices

## Exercises Dataset

Source: https://github.com/hasaneyldrm/exercises-dataset
Pinned commit: `118e4bd6b14da6df0e36605d7169b65db18389a4`

From this dataset, Trainote includes only the structure, exercise metadata, and instruction text/translations. Its exercise images and GIFs are not included. The separately licensed offline sample is listed below.

MIT License

Copyright (c) 2026 Hasan Emir Yıldırım

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation and data files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Recovery anatomy illustrations

Source: https://github.com/crmapache/js-rich-body-highlighter
Pinned commit: `107dafe86f91298d66a41ff1c7b7251b073983d8`

The front/back PNG illustrations and converted native muscle masks are distributed
under MIT. Full notice: `ANATOMY-LICENSE.txt`; import details: `ANATOMY-PROVENANCE.md`.

## Offline push-up demonstration

Source: https://github.com/AssiamahS/opengym3d
Pinned commit: `ea3a60130fdcfb3c4771e44d09f84ebab4ee9bae`

The rendered push-up sample uses the upstream asset explicitly marked CC0, with
a MakeHuman/MPFB body and Mesh2Motion motion. Full OpenGym3D MIT notice:
`EXERCISE-MEDIA-LICENSE.txt`; source checksum and local processing:
`EXERCISE-MEDIA-PROVENANCE.md`. This does not license every upstream animation.

## Qwen3-0.6B on-device report model

Source: https://huggingface.co/Qwen/Qwen3-0.6B
Pinned revision: `c1899de289a04d12100db370d81485cdf75e47ca`
License: Apache License, Version 2.0. Full unmodified license: `QWEN-LICENSE.txt`.

Trainote converts the official BF16 source to GGUF and quantizes directly to
Q4_K_M with the pinned llama.cpp engine. This is a modified/quantized distribution,
not an upstream-provided Q4 file. Bundled filename: `qwen3-0.6b-q4_k_m.gguf`.
SHA-256: `53752fac90c59e3d8de573f3b2dd33046abdfa0254db275d0f51ffc248997734`.
The model is used only to select precomputed fact and action IDs on device.
Full source/build identity is available offline in `MODEL-PROVENANCE.md`.

## llama.cpp inference engine

Source: https://github.com/ggml-org/llama.cpp
Pinned release: `b11912`
Pinned source commit: `961c376a2daa42220ec09663b9bde32c5fba1f70`
License: MIT. Copyright (c) 2023-2026 The ggml authors.
Full unmodified license: `LLAMA-LICENSE.txt`.

Trainote uses the official iOS device binary and a Simulator slice built from
this pinned source. No runtime service is required. Build and artifact checksums
are available offline in `MODEL-PROVENANCE.md`.
