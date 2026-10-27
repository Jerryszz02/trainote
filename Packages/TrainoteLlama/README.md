# TrainoteLlama

Local SPM wrapper around a pinned official llama.cpp engine. Run `python3 Scripts/on-device-ai/prepare.py --engine-only` from the repository root before resolving this package. Generated `Artifacts/` is intentionally ignored. Source release, checksums, build recipe and third-party notices are in `Models/manifest.json`, `Scripts/on-device-ai/prepare.py` and `LICENSE.txt`.

The iOS device slice is official b11912; the missing simulator slice is built from b11912 by its official `build-xcframework.sh ios-sim`. Both minimum deployment versions are 16.4, compatible with iOS 17. macOS is included solely for reproducible development evaluation.
