# n0tfluid — Build Plan & Suggested Improvements

Living roadmap. **v0.2 executed** major Phase A–D items below.

---

## Where we are (v0.2)

| Area | Status |
|------|--------|
| Menu bar dictation | ✅ |
| Configurable PTT hotkey presets | ✅ Right ⌥ / Right ⌘ / F13 / ⌥Space |
| macOS Speech + Whisper | ✅ |
| Translate → English | ✅ Whisper |
| Rewrite selected text mode | ✅ (rule-based + selection AX) |
| Auto-paste GUI + Terminal | ✅ |
| Live partials in overlay | ✅ (Apple Speech streaming while held) |
| Smart punctuation / spacing | ✅ |
| Dictionary replacements | ✅ |
| Speed presets + warm Whisper | ✅ |
| Permission doctor banner | ✅ |
| In-app Whisper model download | ✅ |
| History search / pin / export | ✅ |
| LLM boost | ❌ removed |
| Stable signing script | ✅ `scripts/sign-stable.sh` |
| Vendor whisper.cpp / notarize | ⏳ backlog |

---

## Executed this cycle

### Phase A — Feel instant
- [x] **Streaming partials** — live Apple Speech partials while holding PTT (`livePartials`)
- [x] **Warm Whisper on launch** — optional preflight
- [x] **English fast preset** — Distil-Whisper Small EN / Balanced / Accurate
- [x] **Permission doctor** — Mic / Accessibility / Speech chips in menu

### Phase B — Control
- [x] **Hotkey presets** in Settings (recorder for arbitrary keys deferred)
- [x] **Dictionary** find→replace store + Settings tab
- [x] **App-aware cleanup** — Terminal-safe vs prose via bundle ID

### Phase C — Intelligence
- [x] **Rewrite mode** — select text, dictate instruction (upper/lower/title/shorter/full replace)
- [x] **App-aware rules** in `TranscriptFormatter.options(forBundleID:)`
- [x] LLM boost removed (not worth complexity)

### Phase D — Ship
- [x] **In-app ggml download** — Settings → Speech → Download
- [x] **sign-stable.sh** — Apple Development identity when available
- [ ] Vendor whisper.cpp binary
- [ ] Notarized GitHub release + Homebrew cask
- [x] PasteTest harness retained

---

## Remaining backlog (priority)

1. True streaming decode for **Whisper** (not only Apple Speech partials)
2. Full **hotkey recorder** (capture any combo)
3. Command mode / Shortcuts
4. VAD hands-free
5. Vendor whisper.cpp + notarized releases
6. Notch-aware overlay layout
7. Per-app engine/profile persistence UI
8. Opt-in latency metrics

---

## Metrics

| Metric | Target | Notes |
|--------|--------|-------|
| Paste after STT | &lt; 300 ms | Achieved for Terminal CGEvent path |
| Live partial first paint | &lt; 500 ms | Depends on Speech auth + device |
| Cold Whisper Small | show in UI | Warm on launch helps |

---

## How to run

```bash
cd ~/Desktop/n0tfluid
./scripts/run.sh
# optional stable sign:
./scripts/sign-stable.sh && ./scripts/run.sh
```

Update this file when shipping v0.3+.
