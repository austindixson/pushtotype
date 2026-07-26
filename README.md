# PushToType (n0tfluid)

**Mac-native push-to-talk dictation** — local-first, glass UI, Terminal-aware paste, **Articulate** mode for AI prompts.

Repo: [github.com/austindixson/pushtotype](https://github.com/austindixson/pushtotype)

- **100% on-device** — audio never leaves your Mac  
- **SwiftUI menu-bar app** — real AppKit/Swift, not Electron  
- **Engine choice** — **macOS Speech** (zero download) or **Whisper** (download open models)  
- **Push-to-talk** — hold `Right ⌥`, speak, release → text pastes into any app (including **Terminal**)  
- **Articulate** — offline restructuring for AI prompts / project ideas  

Full roadmap: **[BUILD_PLAN.md](./BUILD_PLAN.md)**

---

## Why Whisper Small?

| Model | Size | Dictation | Translate → EN | Notes |
|-------|------|-----------|----------------|-------|
| **Whisper Small** ⭐ | ~466 MB | Excellent | Yes | Best small balance |
| Whisper Base | ~142 MB | Good | Yes | Faster, lighter |
| Whisper Tiny | ~75 MB | OK | Yes | Lowest resource |
| Small.en | ~466 MB | Excellent EN | No | English-only sharpening |
| Distil-small.en | ~166 MB | Strong EN | No | Fast distilled English |

FluidVoice leans on Parakeet for raw speed (great for English). **n0tfluid** bets on **Whisper** because it’s still the strongest small *open* model that does **both** multilingual dictation **and** speech translation — via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal on Apple Silicon.

---

## Features (v0.2)

- Global **push-to-talk** with presets (Right ⌥ / Right ⌘ / F13 / ⌥Space)
- **Dictate** · **Translate → English** · **Rewrite selection**
- **macOS Speech** or **Whisper** + **speed presets** (Fast English / Balanced)
- **Live partials** in the overlay while you hold the hotkey
- **Fast auto-paste** — GUI (AX) + Terminal (⌘V path)
- **Smart punctuation**, **dictionary** replacements, app-aware cleanup
- **Permission doctor** chips in the menu
- **In-app Whisper model download**
- History search / pin / export · Quit / Test paste

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
cd ~/Desktop/n0tfluid
./scripts/run.sh          # build if needed + launch (avoids Gatekeeper trash)
```

First-time Whisper setup:

```bash
brew install whisper-cpp
./scripts/download-model.sh small
./scripts/run.sh
```

### Permissions

1. **Microphone**  
2. **Accessibility** (required to paste into other apps / Terminal)  
3. **Speech Recognition** (only if using macOS Speech engine)  

System Settings → Privacy & Security → enable **NotFluid**.  
After an ad-hoc rebuild, re-check Accessibility if paste stops working.

If macOS blocks the app: right-click `dist/NotFluid.app` → **Open**, or use `./scripts/run.sh`.

---

## Usage

| Action | How |
|--------|-----|
| Dictate | Hold **Right ⌥**, speak, release |
| Translate → English | Mode → Translate, then PTT (Whisper engine) |
| See result | Overlay shows transcript after paste |
| Copy / paste last | Menu bar panel |
| Test paste | Menu → **Test paste** (click a text field first) |
| Quit | Menu → **Quit n0tfluid** |

---

## Project layout

```
n0tfluid/
├── BUILD_PLAN.md       # Full roadmap & phases
├── Sources/NotFluid/
│   ├── App/            # SwiftUI app + AppState
│   ├── Audio/          # 16 kHz mono WAV capture
│   ├── Transcription/  # Whisper + Apple Speech
│   ├── Input/          # Hotkey + text injection (Terminal-aware)
│   ├── UI/             # Menu bar, overlay, settings
│   ├── Models/
│   └── Services/
├── Resources/
├── scripts/            # run, build, setup, download-model
├── Models/             # local ggml (gitignored)
└── dist/NotFluid.app
```

---

## Dev

```bash
swift build -c release --product NotFluid
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

Models: `~/Library/Application Support/NotFluid/Models/`

---

## Privacy

- No accounts, no cloud STT by default  
- Temporary WAVs deleted after transcription  
- History is local JSON only  
---

## License

MIT — yours to hack on.

Not affiliated with FluidVoice / altic-dev.
