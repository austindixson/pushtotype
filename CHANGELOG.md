# Changelog

## [Unreleased]

- A live partial is sent only when the revoke count it just read is still current, so a buffer cannot slip out after the request was cleared. Pull request: https://github.com/austindixson/pushtotype/pull/6

### Pull request 5

- The live-partial feed flag and speech request are updated together under a lock, so a microphone buffer cannot reach Apple after you switch engines or stop. Pull request: https://github.com/austindixson/pushtotype/pull/5

### Pull request 4

- Changing the engine while you hold the hotkey stops the current live partials and opens them again for the engine you picked. Switching away from macOS Speech does not keep sending that audio to Apple. Pull request: https://github.com/austindixson/pushtotype/pull/4

### Pull request 3

- Live partials stay on this Mac unless you chose macOS Speech. If on-device recognition is unavailable, those partials are skipped instead of being sent to Apple. Pull request: https://github.com/austindixson/pushtotype/pull/3

### Pull request 2

Pull request: https://github.com/austindixson/pushtotype/pull/2

- macOS Speech stays the first-run engine, because it needs no download and has not been measured yet. Whisper Small.en is the recommended model when you pick Whisper, and the model list marks it recommended. A saved engine or Whisper model is left as you set it. If that model is not on disk, or whisper-cli is missing, the take uses on-device macOS Speech and says so. That fallback does not send the audio to Apple. If on-device recognition is unavailable, you get the Whisper message instead. `scripts/setup.sh` and `scripts/download-model.sh` download Whisper Small.en. Benchmark notes are in `docs/benchmarks.md`.
- Dictionary: "use effect" becomes useEffect, "open IAPI" and "openRE API" become OpenAI API, "gitribase" and "getra base" become git rebase, and "postgars" and "postgas" become Postgres. "jason" still becomes JSON only in code and shell.

### From pull request 1

Pull request: https://github.com/austindixson/pushtotype/pull/1

### Added

- Dictation engines: macOS Speech (`SFSpeechRecognizer`), Whisper (whisper.cpp), Parakeet TDT 0.6B v2 and v3 (onnx-asr, int8), Phonon 2 (fermion-research 0.2.4, MLX), OpenAI transcription (`gpt-4o-transcribe`, then `whisper-1`) with the API key in the Keychain, and Conway Research Underdog Bark 3.0, Bark 3.0 Clean, and Bark 3.0 Plus (MLX, weights downloaded at a pinned Hugging Face revision).
- Dev-jargon dictionary: 293 terms and 83 spoken-form corrections (code-only rows such as "jason" → JSON stay out of prose). Your own replacements still win, and everyday words are blocked.
- `DictationDefaults.engine`, one line that sets the engine when you have not chosen one. Benchmark notes live in `docs/benchmarks.md`.
- `LICENSE` (MIT, Austin Dixson, 2026) and `NOTICE` (CC-BY-4.0 for NVIDIA Parakeet TDT 0.6B v3 and each Bark model, plus the other model and runtime notices).
- GitHub Actions workflow that builds an ad-hoc signed `PushToType.app` zip when a version tag is pushed. The actions are pinned to commit SHAs. No notarization.

### Changed

- The app name is PushToType. The bundle id is `dev.pushtotype.app`. The first launch copies `~/Library/Application Support/NotFluid` and the old preferences domain `dev.n0tfluid.app` when the new locations are empty. Microphone, Speech Recognition, and Accessibility have to be granted again.
- Distil-small.en downloads `ggml-distil-small.en.bin` from `distil-whisper/distil-small.en` (336,191,657 bytes, SHA-256 pinned). The old `ggerganov/whisper.cpp` URL 404s.
- README quick start is a clone of this repo, not `~/Desktop/n0tfluid`.
- User dictionary finds match whole words only, including phrases. kube → k8s does not fire inside kubectl, and you know → YK does not fire inside "you knowledge" or "bayou know".
- User dictionary replacements are literal. `$1` and backslashes are not regex templates. An empty replacement deletes the matched word. Leading and trailing whitespace on a replacement is trimmed, and a whitespace-only replacement still deletes the word.
- Bark's `bark_mlx.py` and `bark_loader.py` are checked against a pinned SHA-256 before they run.
- The idle overlay label is PUSHTOTYPE.
- The empty-spoken `aws` row was removed. It duplicated AWS and had no correction. The two JSON rows stay: "j son" applies in prose, and "jason" applies only in code and shell.

### Not included

- Bark 2.0 4-bit. `ConwayResearch/bark-0.6B-4bit-v2.0` does not ship `model.bark` or `bark_mlx.py`, so it does not use the Bark 3.0 loader.
