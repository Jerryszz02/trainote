# Offline report model

Selected: Qwen3-0.6B, Apache-2.0; exact revisions, SHA-256 values and output size are in `manifest.json`. `QWEN-LICENSE.txt` is the upstream license. The app never downloads weights at runtime.

On an Apple Silicon Mac with Xcode and Python 3.9+:

```sh
python3 Scripts/on-device-ai/prepare.py > .local-ai-cache/prepare.log 2>&1
python3 Scripts/on-device-ai/evaluate.py > .local-ai-cache/evaluation.log 2>&1
python3 Scripts/on-device-ai/evaluate-stress.py > .local-ai-cache/stress-evaluation.log 2>&1
```

Create `.local-ai-cache` before redirecting a first run. Preparation obtains official BF16 safetensors, verifies them, converts to BF16 GGUF using pinned llama.cpp, then quantizes directly to Q4_K_M. It never requantizes Q8. The official Q8_0 is a separate comparison. All large inputs and generated binaries are ignored. Python tools are isolated in `.local-ai-cache/venv`; dependencies are pinned in `Scripts/on-device-ai/requirements.txt`.

The official b11912 XCFramework contains iOS arm64 and macOS slices. The preparation script builds the missing iOS Simulator arm64/x86_64 slice from that exact source and combines them. All iOS slices have minimum deployment 16.4 and support this app's iOS 17 target. `python3 Scripts/on-device-ai/prepare.py --engine-only` prepares only engine inputs for rules/mock CI (no model weights). The local SPM package expects the prepared ignored artifact.

The Xcode post-build phase checks the selected model SHA-256 and copies it into app resources. Release fails when weights are absent or changed. Debug explicitly permits a rules-only build if absent (`TRAINOTE_RULES_ONLY_BUILD=YES`); if weights exist, they must still pass verification. For a model-bearing Release archive run full preparation first. Bundle identity is pinned, without runtime updates.

The checked-in 32 evaluation fixtures, 8 distinct tuning fixtures and 8 separate resource stress cases contain synthetic data only. `evaluate.py` runs the actual Swift runtime with the production prompt string and GBNF-equivalent selection schema. It fails if the production system string drifts. Automatic structural/priority checks do not constitute human quality review or iPhone performance validation. See `docs/app-store/on-device-model-evaluation.md` for actual measured limits.
