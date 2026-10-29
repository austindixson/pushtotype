# PushToType

**Mac push-to-talk dictation.** Local engines keep audio on your Mac. Glass menu-bar UI, Terminal-aware paste, and Articulate mode for AI prompts.

Repo: [github.com/austindixson/pushtotype](https://github.com/austindixson/pushtotype)

- **Local by default** — Whisper, Parakeet, Phonon 2, and Bark keep audio on your Mac. macOS Speech is built in and, when you choose it, can send audio to Apple. OpenAI is optional and sends audio only when you pick it.
- **SwiftUI menu-bar app** — AppKit/Swift
- **Push-to-talk** — hold `Right ⌥`, speak, release. Text pastes into the app you were typing in, including Terminal.
- **Articulate** — offline restructuring for AI prompts and project ideas
- **Dev dictionary** — spoken names like "ver cell" and "engine x" are corrected after transcription

macOS Speech stays the first-run engine (`DictationDefaults.engine` in `Sources/PushToTypeSupport/EngineCatalog.swift`), because it needs no download and has not been measured yet. Whisper Small.en is the recommended local model when you pick Whisper (`DictationDefaults.whisperModel`). A saved engine or model is left as you set it. Measured numbers are in [docs/benchmarks.md](./docs/benchmarks.md).

## From the maker of Super Notch

Super Notch is mission control for your AI coding agents, $20 once.

https://www.supernotch.ai/?utm_source=github&utm_medium=readme&utm_campaign=pushtotype

Full roadmap: **[BUILD_PLAN.md](./BUILD_PLAN.md)**

---

## Why Whisper Small.en?

macOS Speech is still what a new install uses. Whisper Small.en is the recommended Whisper model: 31 of 36 jargon terms before corrections, 3.2% WER on read speech, and 0.72 s median latency on the M1 Max run in [docs/benchmarks.md](./docs/benchmarks.md).

| Model | Size | Dictation | Translate → EN | Notes |
|-------|------|-----------|----------------|-------|
| **Small.en** | 488 MB | English | No | Recommended Whisper model |
| Whisper Small | 488 MB | Strong | Yes | Multilingual plus translate |
| Whisper Base | 148 MB | Good | Yes | Faster, lighter |
| Whisper Tiny | 78 MB | OK | Yes | Smallest ggml file |
| Distil-small.en | 336 MB | English | No | Official ggml from distil-whisper |

Sizes are the files Hugging Face serves, in decimal MB. Distil-small.en used to point at a missing file on `ggerganov/whisper.cpp` and was labeled 166 MB. The file that actually exists is `distil-whisper/distil-small.en` `ggml-distil-small.en.bin`, 336,191,657 bytes.

Whisper still does multilingual dictation and speech translation through [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Parakeet, Phonon 2, and Bark are faster English (or, for Parakeet v3, multilingual) options and do not translate.

---

## Features

- Global **push-to-talk** with presets (Right ⌥ / Right ⌘ / F13 / ⌥Space)
- **Dictate**, **Translate → English** (Whisper), **Rewrite selection**, **Articulate**
- Engines:
  - **macOS Speech** (`SFSpeechRecognizer`) — no download. Choosing this engine can send audio to Apple, including live partials
  - **Whisper** — whisper.cpp. Small.en is the recommended model. Multilingual Small still translates. Models download when you ask
  - **Parakeet** — NVIDIA Parakeet TDT 0.6B v2 and v3, int8 ONNX via onnx-asr
  - **Phonon 2** — Fermion Research, English, Apple silicon, MLX
  - **Bark 3.0**, **Bark 3.0 Clean**, **Bark 3.0 Plus** — Conway Research Underdog Bark, MLX on Apple silicon
  - **OpenAI** — `gpt-4o-transcribe`, then `whisper-1`, with your API key in the Keychain
- Dev-jargon dictionary (hosting, frameworks, languages, and the spoken forms people actually say) plus your own replacements
- **Live partials** in the overlay while you hold the hotkey. On-device for every engine except macOS Speech, which can use Apple's servers
- **Auto-paste** — GUI (Accessibility) and Terminal (⌘V)
- **Smart punctuation** and app-aware cleanup
- Permission chips in the menu
- In-app model download, with size and SHA-256 check
- History search / pin / export

Bark 2.0 4-bit is not included. That Hugging Face repo is a different package (MLX safetensors and ONNX), not the `model.bark` file the Bark 3.0 loader reads.

Model ids, URLs, sizes, and runtimes are listed in [docs/benchmarks.md](./docs/benchmarks.md). Licenses are in [NOTICE](./NOTICE).

---

## Suggested improvements

Prioritized backlog (detail in [BUILD_PLAN.md](./BUILD_PLAN.md)):

### Do next (high impact)

1. **Streaming partials** — words appear in the overlay while you speak  
2. **Custom hotkey recorder** — pick any key in Settings (not only Right ⌥)  
3. **Faster STT presets** — warm model on launch; English “fast” (Base / Distil / Parakeet later)  
4. **Permission doctor** — clear Mic / Accessibility status + one-click fix (rebuilds reset Accessibility on ad-hoc sign)  
5. **Stable dev signing** — keep Accessibility across rebuilds  

### Quality

6. **App-aware cleanup** — Terminal keeps shell-safe text; Mail/Slack get nicer prose  
7. **Personal dictionary** — force spellings / expansions  
8. **History search / re-paste / export**  
9. **Per-app profiles** — different engine or prompt per app  

### Product depth

11. **Command mode** — “open Safari”, Shortcuts, allowlisted shell  
12. **Rewrite selection** — select text → hold key → rewrite  
13. **Notch-aware overlay**  
14. **VAD / hands-free** — start on speech, stop on silence  
15. **Clearer multilingual UX**  

### Ship

16. **In-app Whisper model download** (progress UI)  
17. **Vendor whisper.cpp** (no Homebrew required)  
18. **Notarized release + Homebrew cask**  
19. **Automated paste tests** (GUI + Terminal)  
20. **Opt-in anonymous metrics only** (never audio/text)  

### Build sequence

| Phase | Focus |
|-------|--------|
| **A — Feel instant** | Streaming partials, warm model, fast English preset, permissions UI |
| **B — Control** | Hotkey recorder, dictionary, per-app profiles |
| **C — Intelligence** | Stronger Articulate, rewrite mode, app-aware rules |
| **D — Ship** | In-app downloads, vendored STT, notarized releases |

---

## Requirements

- macOS 14+ (Sonoma or later)  
- Apple Silicon recommended (Metal / whisper.cpp)  
- [Homebrew](https://brew.sh) (for whisper-cpp)  
- Xcode / CLT  

---

## Quick start

```bash
git clone https://github.com/austindixson/pushtotype.git
cd pushtotype
./scripts/setup.sh        # Homebrew whisper.cpp, recommended Whisper Small.en, then build
./scripts/run.sh          # launch (clears quarantine if Gatekeeper marked the app)
```

`./scripts/run.sh` alone builds first if `dist/PushToType.app` is missing.

Whisper Small.en only, if you already have the toolchain:

```bash
brew install whisper-cpp
./scripts/download-model.sh small.en
./scripts/run.sh
```

The app still starts on macOS Speech. Small.en is selected when you switch to Whisper and have not chosen a model. If that file is missing, the take uses macOS Speech and the menu says so. Multilingual Whisper Small remains available for translate.

Other engines are downloaded from Settings after you select them. Parakeet, Phonon 2, and Bark need Apple silicon for their local runtimes. macOS Speech needs no download.

### If you used an older build

The bundle id changed from `dev.n0tfluid.app` to `dev.pushtotype.app`, and files moved from `~/Library/Application Support/NotFluid` to `~/Library/Application Support/PushToType`.

On first launch the app copies the old support folder when the new one is absent, and copies UserDefaults from the old preferences domain when you have not chosen an engine yet. macOS ties Microphone, Speech Recognition, and Accessibility to the bundle id, so grant those again for PushToType.

### Permissions

1. **Microphone**  
2. **Accessibility** (required to paste into other apps / Terminal)  
3. **Speech Recognition** (only if using macOS Speech engine)  

System Settings → Privacy & Security → enable **PushToType**.  
After an ad-hoc rebuild, re-check Accessibility if paste stops working.

Release builds from GitHub Actions are ad-hoc signed (`codesign -s -`), not notarized. macOS will warn the first time. Right-click `PushToType.app` → **Open**, or in Terminal:

```bash
xattr -cr PushToType.app
open PushToType.app
```

`./scripts/run.sh` clears the quarantine attribute and re-signs ad-hoc if the signature is missing. A local Apple Development certificate, when you have one, is still preferred so Accessibility survives rebuilds. The tag workflow does not have a signing certificate, so it always uses the ad-hoc signature.

---

## Usage

| Action | How |
|--------|-----|
| Dictate | Hold **Right ⌥**, speak, release |
| Translate → English | Mode → Translate, then PTT (Whisper engine) |
| See result | Overlay shows transcript after paste |
| Copy / paste last | Menu bar panel |
| Test paste | Menu → **Test paste** (click a text field first) |
| Quit | Menu → **Quit PushToType** |

---

## Project layout

```
pushtotype/
├── BUILD_PLAN.md       # Full roadmap & phases
├── Sources/PushToType/
│   ├── App/            # SwiftUI app + AppState
│   ├── Audio/          # 16 kHz mono WAV capture
│   ├── Transcription/  # Speech, Whisper, Parakeet, Phonon, Bark, OpenAI
│   ├── Input/          # Hotkey + text injection (Terminal-aware)
│   ├── UI/             # Menu bar, overlay, settings
│   ├── Models/
│   └── Services/
├── Resources/
├── scripts/            # run, build, setup, download-model
├── Models/             # local ggml (gitignored)
└── dist/PushToType.app
```

---

## Dev

```bash
swift build -c release --product PushToType
./scripts/build-app.sh
./scripts/run.sh

# Paste regression (TextEdit + AX)
swift build --product PasteTest && .build/debug/PasteTest

# Post-STT path benchmark (raw vs punctuation vs Articulate)
./scripts/benchmark-boost.sh
```

### Post-STT benchmark

Compares offline paths on fixed fixtures (no mic):

| Path | What it measures |
|------|------------------|
| STT only | Raw transcript |
| + smart punctuation | Rule cleanup |
| + Articulate | Offline idea restructuring |

```bash
./scripts/benchmark-boost.sh
```

Models: `~/Library/Application Support/PushToType/Models/`

---

## Privacy

Local engines keep audio on your Mac. Whisper, Parakeet, Phonon 2, and Bark do not send the recording or live partials off this Mac. If on-device recognition is unavailable, those engines skip live partials instead of sending them to Apple.

macOS Speech is the exception. When you choose that engine, recognition can use Apple's servers, including the words that appear while you hold the hotkey.

There is no analytics, telemetry, or account. The only network calls in the app are:

- **Model downloads**, when you start them: Hugging Face for Whisper, Parakeet, Bark, and Phonon 2 weights. Phonon setup also downloads the uv installer from GitHub and Python packages from PyPI. Parakeet and Bark setup install their Python packages from PyPI.
- **OpenAI transcription**, only if that engine is selected: `POST https://api.openai.com/v1/audio/transcriptions` with the recording and your key. The key is stored in the Keychain under `dev.pushtotype.app`. It is not in the source.
- **macOS Speech**, only if you choose that engine: Apple may receive the audio for recognition and for live partials. The other engines do not use that path.

Temporary WAV files are deleted after transcription. History is a local JSON file. The dev dictionary and your replacements stay on disk in Application Support.

---

## License

MIT. See [LICENSE](./LICENSE).

Third-party models keep their own licenses. Parakeet, Phonon 2, and the Bark models are CC-BY-4.0. Attribution is in [NOTICE](./NOTICE). Weights are not in this repository.

Bark models: Conway Research, Underdog Bark 3.0, 3.0 Clean, and 3.0 Plus. NVIDIA Parakeet TDT 0.6B v3 is an upstream of Phonon 2 and Bark, and v2/v3 are what the Parakeet engine runs (ONNX builds by istupakov, same CC-BY-4.0).

Not affiliated with FluidVoice / altic-dev.
