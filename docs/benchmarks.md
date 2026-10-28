# Benchmarks

Numbers below are blank on purpose. Fill them in after a run on a real Mac.
Use the same model id, URL, and runtime listed here. The default engine is
`DictationDefaults.engine` in `Sources/PushToTypeSupport/EngineCatalog.swift`.
Change that one line after this table has times.

Suggested columns once you have a recording: model load, seconds of audio,
transcription seconds, and a short note about accuracy. Do not commit audio.

| Engine | Model id | Runtime | Download | Bytes | SHA-256 | Load | Transcribe | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| macOS Speech | macos-sfspeechrecognizer | Apple Speech.framework (SFSpeechRecognizer) | none |  |  |  |  | On-device when the recognizer allows it |
| Whisper Tiny | ggml-tiny | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.bin | 77691713 | be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21 |  |  | |
| Whisper Base | ggml-base | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin | 147951465 | 60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe |  |  | |
| Whisper Small | ggml-small | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin | 487601967 | 1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b |  |  | Also the translate-to-English model |
| Whisper Small.en | ggml-small.en | whisper.cpp (ggml) | https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.en.bin | 487614201 | c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d |  |  | English only |
| Distil-Whisper Small EN | distil-small.en | whisper.cpp (ggml) | https://huggingface.co/distil-whisper/distil-small.en/resolve/9e4a67ca4569c30be43a3fe7fba1621e504f0093/ggml-distil-small.en.bin | 336191657 | 7691eb11167ab7aaf6b3e05d8266f2fd9ad89c550e433f86ac266ebdee6c970a |  |  | Official ggml. Not the old 404 URL |
| Parakeet TDT 0.6B v2 int8 | nemo-parakeet-tdt-0.6b-v2 | onnx-asr (ONNX Runtime, int8) | https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/tree/0bbb45a3365852604aef28b538a8f066f4ccaa85 | 661322064 | see EngineCatalog.swift |  |  | English. Three ONNX files |
| Parakeet TDT 0.6B v3 int8 | nemo-parakeet-tdt-0.6b-v3 | onnx-asr (ONNX Runtime, int8) | https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/tree/8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce | 670525767 | see EngineCatalog.swift |  |  | Multilingual |
| Phonon 2 | phonon-2 | fermion-research 0.2.4 on MLX | https://huggingface.co/FermionResearch/Phonon-2/resolve/3e6ab3a81d73b4d424ff34cc72535deb606378ef/phonon-2.bps.tar.zst | 163515201 | 98125795b6dda72f5c6eee9ba33d19815df65dcb18b50a357bf9f73c9935309e |  |  | English, Apple silicon |
| OpenAI | gpt-4o-transcribe | OpenAI Audio transcriptions API | https://api.openai.com/v1/audio/transcriptions |  |  |  |  | Fallback model whisper-1. User key in Keychain |
| Bark 3.0 | Underdog-Bark-3.0 | mlx-audio Parakeet graph via bark_mlx.py | https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/resolve/85db2ad18ab41e534a222ee253c29191d77ed919/model.bark | 163398645 | c18de9418d73cbeb80b8c1287b392d480a56e191ef4a81d1baaa1b02e66d92ed |  |  | English, Apple silicon |
| Bark 3.0 Clean | Underdog-Bark-3.0-Clean | mlx-audio Parakeet graph via bark_mlx.py | https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Clean/resolve/6d34ed8639b2b9a33e764acf06748519bbb950cf/model.bark | 179458613 | b67ca90d94b79a36af4616f1cb3f241884925de7aa9f3e673a8d5c6c4cfd3436 |  |  | Drops fillers and false starts |
| Bark 3.0 Plus | Underdog-Bark-3.0-Plus | mlx-audio Parakeet graph via bark_mlx.py | https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Plus/resolve/d4fab2f8b95681e5ad3cfb4e8c5f4e0c009b3deb/model.bark | 179524845 | fdd9f1052e4fdead07d71e8cd2138813eb0c209fd6ff8b1b6f47737e1e501857 |  |  | Same loader as Bark 3.0 |

Bark 2.0 4-bit (`ConwayResearch/bark-0.6B-4bit-v2.0`) is omitted. It publishes MLX safetensors and ONNX, not `model.bark`, so `bark_mlx.py` cannot load it.
