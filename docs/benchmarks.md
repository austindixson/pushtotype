# Benchmarks

Measured on 2026-10-28 on an Apple M1 Max (10 cores, 64 GB) running macOS 26.5.2, at commit `9781955`, using each
engine's pinned weights and the app's own worker code path. The machine was shared with other jobs (load average 4.5
to 25), so treat the latencies as upper bounds. Eleven engines were measured. Two were not: macOS Speech and OpenAI.

The default engine is `DictationDefaults.engine` in `Sources/PushToTypeSupport/EngineCatalog.swift`.

## Test set

The set has 45 clips totalling 326 s of audio:

- 24 TTS clips: 12 developer-jargon sentences, each spoken by the macOS voices Samantha and Daniel.
- 20 LibriSpeech dev-clean clips of 2 to 18 s.
- One 121 s LibriSpeech clip, standing in for a long take.

How the numbers were measured:

- **WER:** the jargon WER ignores case and punctuation. "Dict" means after `TranscriptFormatter` and
  `DictationCorrections` in a code app.
- **Latency:** the time from sending the take to receiving the text, over 44 short clips × 3 sessions. For Whisper
  this includes process start and model load, which happen on every take.
- **Memory:** `phys_footprint`, which is what Activity Monitor shows as "Memory". Audio is not committed.

## Accuracy and speed

| Engine | Jargon WER raw → dict | Jargon terms (/36) raw → dict | Read-speech WER | 2-min take WER | Latency median / p95 | 2-min take latency |
| --- | --- | --- | --- | --- | --- | --- |
| macOS Speech | not measured | | | | | |
| Whisper Tiny | 13.8% → 11.0% | 24 → 28 | 8.1% | 29.6% | 0.33 s / 0.47 s | 2.0 s |
| Whisper Base | 15.6% → 11.9% | 21 → 26 | 8.1% | 27.0% | 0.46 s / 0.62 s | 2.4 s |
| Whisper Small | 11.0% → 7.8% | 25 → 29 | 5.2% | 25.9% | 0.93 s / 1.31 s | 4.9 s |
| **Whisper Small.en** | **5.5% → 4.6%** | **31 → 32** | 3.2% | 8.0% | 0.72 s / 1.00 s | 5.3 s |
| Distil-Whisper Small EN | 17.0% → 11.0% | 18 → 26 | 4.1% | 44.9% (loops) | 0.56 s / 0.72 s | 7.6 s |
| Parakeet TDT 0.6B v2 int8 | 6.4% → 4.6% | 30 → 32 | **2.3%** | **2.9%** | 0.69 s / 2.06 s | 22.5 s |
| Parakeet TDT 0.6B v3 int8 | 6.9% → 4.6% | 29 → 32 | 4.1% | 4.7% | 0.78 s / 2.31 s | 28.4 s |
| Phonon 2 | 13.8% → 9.6% | 21 → 26 | 2.6% | 4.4% | **0.11 s / 0.24 s** | **1.9 s** |
| OpenAI | not measured | | | | | |
| Bark 3.0 | 20.2% → 14.7% | 16 → 23 | 3.8% | 5.1% | 0.31 s / 0.79 s | 7.5 s |
| Bark 3.0 Clean | 24.3% → 13.3% | 16 → 26 | 2.9% | 3.6% | 0.16 s / 0.47 s | 2.5 s |
| Bark 3.0 Plus | 20.6% → 16.1% | 18 → 23 | 3.2% | 5.1% | 0.30 s / 0.73 s | 7.6 s |

## Footprint

| Engine | Model id | Runtime | Download | Bytes | SHA-256 | Load | Idle memory | Peak memory (short take / 2-min take) | Disk | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| macOS Speech | macos-sfspeechrecognizer | Apple Speech.framework (SFSpeechRecognizer) | none | | | | | | 0 | Not measured: needs a person to grant Speech Recognition permission, and it streams live from the microphone |
| Whisper Tiny | ggml-tiny | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.bin | 77691713 | be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21 | 0.05 s per take | 0 (no resident process) | 177 MB / 231 MB | 80 MB | |
| Whisper Base | ggml-base | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin | 147951465 | 60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe | 0.07 s per take | 0 | 271 MB / 325 MB | 144 MB | |
| Whisper Small | ggml-small | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin | 487601967 | 1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b | 0.18 s per take | 0 | 672 MB / 727 MB | 465 MB | Also the translate-to-English model. Drops about 58 words of a 2-min take (the same with `-l en`) |
| Whisper Small.en | ggml-small.en | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.en.bin | 487614201 | c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d | 0.18 s per take | 0 | 671 MB / 734 MB | 465 MB | English only. Recommended default |
| Distil-Whisper Small EN | distil-small.en | whisper.cpp (ggml) | https://huggingface.co/distil-whisper/distil-small.en/resolve/9e4a67ca4569c30be43a3fe7fba1621e504f0093/ggml-distil-small.en.bin | 336191657 | 7691eb11167ab7aaf6b3e05d8266f2fd9ad89c550e433f86ac266ebdee6c970a | 0.13 s per take | 0 | 480 MB / 564 MB | 336 MB | Official ggml, not the old 404 URL. Repeats itself on long takes |
| Parakeet TDT 0.6B v2 int8 | nemo-parakeet-tdt-0.6b-v2 | onnx-asr 0.12 (ONNX Runtime 1.28, int8) | https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/tree/0bbb45a3365852604aef28b538a8f066f4ccaa85 | 661322064 | see EngineCatalog.swift | 6.5 s | 1.2 GB | 5.5 GB / **47.6 GB** | 631 MB + 125 MB venv | English. No chunking, so memory grows with take length; needs chunking before it is safe for long takes |
| Parakeet TDT 0.6B v3 int8 | nemo-parakeet-tdt-0.6b-v3 | onnx-asr 0.12 (ONNX Runtime 1.28, int8) | https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/tree/8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce | 670525767 | see EngineCatalog.swift | 7.4 s | 1.25 GB | 5.5 GB / **47.6 GB** | 639 MB + 125 MB venv | Multilingual. Same chunking issue. Returned empty text on one 1.9 s clip |
| Phonon 2 | phonon-2 | fermion-research 0.2.4 on MLX 0.32 | https://huggingface.co/FermionResearch/Phonon-2/resolve/3e6ab3a81d73b4d424ff34cc72535deb606378ef/phonon-2.bps.tar.zst | 163515201 | 98125795b6dda72f5c6eee9ba33d19815df65dcb18b50a357bf9f73c9935309e | 13.5 s | 3.1 GB | 4.9 GB / 7.1 GB | 325 MB + 1.0 GB venv | English, Apple silicon. Fastest |
| OpenAI | gpt-4o-transcribe | OpenAI Audio transcriptions API | https://api.openai.com/v1/audio/transcriptions | | | | | | 0 | Not measured (paid and needs a key). Fallback model whisper-1. User key in Keychain |
| Bark 3.0 | Underdog-Bark-3.0 | mlx-audio 0.5 Parakeet graph via bark_mlx.py | https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/resolve/85db2ad18ab41e534a222ee253c29191d77ed919/model.bark | 163398645 | c18de9418d73cbeb80b8c1287b392d480a56e191ef4a81d1baaa1b02e66d92ed | 1.7 s (first run 26.9 s) | 1.4 GB | 7.3 GB / 9.5 GB | 1.35 GB + 435 MB venv | English, Apple silicon. The first run writes a 1.2 GB `mlx-cache-fp16` |
| Bark 3.0 Clean | Underdog-Bark-3.0-Clean | mlx-audio 0.5 Parakeet graph via bark_mlx.py | https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Clean/resolve/6d34ed8639b2b9a33e764acf06748519bbb950cf/model.bark | 179458613 | b67ca90d94b79a36af4616f1cb3f241884925de7aa9f3e673a8d5c6c4cfd3436 | 1.5 s (first run 20.7 s) | 1.4 GB | 7.2 GB / 9.4 GB | 1.37 GB + venv | Drops fillers and false starts. Same 1.2 GB cache |
| Bark 3.0 Plus | Underdog-Bark-3.0-Plus | mlx-audio 0.5 Parakeet graph via bark_mlx.py | https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Plus/resolve/d4fab2f8b95681e5ad3cfb4e8c5f4e0c009b3deb/model.bark | 179524845 | fdd9f1052e4fdead07d71e8cd2138813eb0c209fd6ff8b1b6f47737e1e501857 | 1.5 s (first run 19.1 s) | 1.4 GB | 7.3 GB / 9.5 GB | 1.37 GB + venv | Same loader as Bark 3.0. Same 1.2 GB cache |

Bark 2.0 4-bit (`ConwayResearch/bark-0.6B-4bit-v2.0`) is omitted. It publishes MLX safetensors and ONNX, not
`model.bark`, so `bark_mlx.py` cannot load it.

## Default

**Whisper Small.en** is the recommended local default:

- It is the best on jargon before corrections (31 of 36 terms) and is within a point of the leaders after corrections.
- It is good on read speech (3.2%).
- It stays under 1 s median latency.
- It uses nothing while idle and about 0.7 GB during a take, and it needs no Python.

The alternatives each have a drawback for a default:

- Parakeet v2 is the most accurate on read speech, but it decodes the whole take at once and hit 47.6 GB on a 2-minute
  take.
- Phonon 2 is the fastest, but it keeps about 3 GB resident and needs a 1 GB venv.
- The Bark models are fast, but they are the weakest on jargon and need about 1.4 GB on disk.

macOS Speech has not been measured yet. Keep it as the first-run engine until it has numbers, because it needs no
download.

## Dictionary gaps found

The run had no entry for "use effect" → useEffect, "Open IAPI" or "OpenRE API" → OpenAI API, "Gitribase" or "getra base" → git rebase, or "postgars" or "postgas" → Postgres. Those spoken forms are in the dictionary now. "jason" → JSON stays limited to code and shell.
