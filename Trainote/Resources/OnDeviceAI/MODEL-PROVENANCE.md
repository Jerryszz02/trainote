# On-device model and engine provenance

These identities describe the bundled report model and inference engine.
Sources are informational; reading this file does not make a network request.

## Qwen3-0.6B

- repository: `Qwen/Qwen3-0.6B`
- revision: `c1899de289a04d12100db370d81485cdf75e47ca`
- sourceSHA256: `f47f71177f32bcd101b7573ec9171e6a57f4f4d31148d38e382306f42996874b`
- license: `Apache-2.0`
- quantization: `Q4_K_M`
- filename: `qwen3-0.6b-q4_k_m.gguf`
- sha256: `53752fac90c59e3d8de573f3b2dd33046abdfa0254db275d0f51ffc248997734`
- bytes: `484220256`

Official model source: https://huggingface.co/Qwen/Qwen3-0.6B
License: Apache-2.0; see QWEN-LICENSE.txt.
Modification: official BF16 source converted to GGUF, then directly quantized to Q4_K_M.

## llama.cpp

- repository: `https://github.com/ggml-org/llama.cpp`
- tag: `b11912`
- sourceSHA256: `bcc26394f51a264fdb26dccda82f35230c6f8b15be5c41cb3cd2cd22a5dd3c48`
- xcframeworkSHA256: `1eba0138d999dd1d109948e6455ba10345d71f229b66167eb9897849bf2a4ae5`
- macosSHA256: `3c826048ae8dc5b1ab60632f6a8a649e5885fa4e80a996f71455c36b83a6598b`
- commit: `961c376a2daa42220ec09663b9bde32c5fba1f70`

License: MIT; see LLAMA-LICENSE.txt.
The device binary comes from the pinned official release. The Simulator slice is built from the same source.
Models and prompts change only with the app version; no runtime model download is provided.
