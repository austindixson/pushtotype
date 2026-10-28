#!/usr/bin/env bash
# Download a whisper.cpp ggml model into Application Support.
# Checksums match WhisperModel in Sources/PushToTypeSupport/EngineCatalog.swift.
set -euo pipefail

MODEL_ID="${1:-small}"
APP_SUPPORT="${HOME}/Library/Application Support/PushToType/Models"
WHISPER_REV="5359861c739e955e79d9a303bcbc70fb988958b1"
DISTIL_REV="9e4a67ca4569c30be43a3fe7fba1621e504f0093"

case "$MODEL_ID" in
  tiny)
    FILE="ggml-tiny.bin"
    URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/${WHISPER_REV}/${FILE}"
    SHA="be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
    ;;
  base)
    FILE="ggml-base.bin"
    URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/${WHISPER_REV}/${FILE}"
    SHA="60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
    ;;
  small)
    FILE="ggml-small.bin"
    URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/${WHISPER_REV}/${FILE}"
    SHA="1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
    ;;
  small.en)
    FILE="ggml-small.en.bin"
    URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/${WHISPER_REV}/${FILE}"
    SHA="c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
    ;;
  distill-small.en|distil-small.en)
    FILE="ggml-distil-small.en.bin"
    URL="https://huggingface.co/distil-whisper/distil-small.en/resolve/${DISTIL_REV}/${FILE}"
    SHA="7691eb11167ab7aaf6b3e05d8266f2fd9ad89c550e433f86ac266ebdee6c970a"
    ;;
  *)
    echo "Unknown model: $MODEL_ID"
    echo "Usage: $0 [tiny|base|small|small.en|distil-small.en]"
    exit 1
    ;;
esac

mkdir -p "$APP_SUPPORT"
if [[ -f "$APP_SUPPORT/$FILE" ]]; then
  echo "$SHA  $APP_SUPPORT/$FILE" | shasum -a 256 -c -
  echo "Already downloaded: $APP_SUPPORT/$FILE"
  exit 0
fi

echo "Downloading $FILE"
echo "  $URL"
TMP="$(mktemp)"
curl -L --fail --progress-bar -o "$TMP" "$URL"
echo "$SHA  $TMP" | shasum -a 256 -c -
mv "$TMP" "$APP_SUPPORT/$FILE"
echo "Saved $APP_SUPPORT/$FILE"
