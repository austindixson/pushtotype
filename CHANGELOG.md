# Changelog

## [Unreleased]

### Added

- Dictation engines: macOS Speech (`SFSpeechRecognizer`), Whisper (whisper.cpp), Parakeet TDT 0.6B v2 and v3 (onnx-asr, int8), Phonon 2 (fermion-research 0.2.4, MLX), OpenAI transcription (`gpt-4o-transcribe`, then `whisper-1`) with the API key in the Keychain, and Conway Research Underdog Bark 3.0, Bark 3.0 Clean, and Bark 3.0 Plus (MLX, weights downloaded at a pinned Hugging Face revision).
- Dev-jargon dictionary: 294 terms and 83 spoken-form corrections (code-only rows such as "jason" → JSON stay out of prose). Your own replacements still win, and everyday words are blocked.
- `DictationDefaults.engine`, one line that sets the engine when you have not chosen one. Benchmark notes live in `docs/benchmarks.md`.
- `LICENSE` (MIT, Austin Dixson, 2026) and `NOTICE` (CC-BY-4.0 for NVIDIA Parakeet TDT 0.6B v3 and each Bark model, plus the other model and runtime notices).
- GitHub Actions workflow that builds an ad-hoc signed `PushToType.app` zip when a version tag is pushed. No notarization.

### Changed

- The app name is PushToType. The bundle id is `dev.pushtotype.app`. The first launch copies `~/Library/Application Support/NotFluid` and the old preferences domain `dev.n0tfluid.app` when the new locations are empty. Microphone, Speech Recognition, and Accessibility have to be granted again.
- Distil-small.en downloads `ggml-distil-small.en.bin` from `distil-whisper/distil-small.en` (336,191,657 bytes, SHA-256 pinned). The old `ggerganov/whisper.cpp` URL 404s.
- README quick start is a clone of this repo, not `~/Desktop/n0tfluid`.

### Not included

- Bark 2.0 4-bit. `ConwayResearch/bark-0.6B-4bit-v2.0` does not ship `model.bark` or `bark_mlx.py`, so it does not use the Bark 3.0 loader.
