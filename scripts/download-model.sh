#!/usr/bin/env bash
# Download a whisper.cpp ggml model into Application Support + project Models/
set -euo pipefail

MODEL_ID="${1:-small}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_MODELS="$ROOT/Models"
APP_SUPPORT="$HOME/Library/Application Support/NotFluid/Models"

case "$MODEL_ID" in
  tiny)   FILE="ggml-tiny.bin" ;;
  base)   FILE="ggml-base.bin" ;;
  small)  FILE="ggml-small.bin" ;;
  small.en) FILE="ggml-small.en.bin" ;;
  distill-small.en|distil-small.en)
    FILE="ggml-distil-small.en.bin"
    MODEL_ID="distil-small.en"
    ;;
  *)
    echo "Unknown model: $MODEL_ID"
    echo "Usage: $0 [tiny|base|small|small.en|distil-small.en]"
    exit 1
    ;;
esac

# Official ggml models hosted for whisper.cpp
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
URL="$BASE_URL/$FILE"

mkdir -p "$PROJECT_MODELS" "$APP_SUPPORT"

if [[ -f "$APP_SUPPORT/$FILE" ]]; then
  echo "✓ Already downloaded: $APP_SUPPORT/$FILE"
  # Keep project copy in sync for dev
  ln -sf "$APP_SUPPORT/$FILE" "$PROJECT_MODELS/$FILE" 2>/dev/null || cp -n "$APP_SUPPORT/$FILE" "$PROJECT_MODELS/$FILE" || true
  exit 0
fi

echo "Downloading Whisper model: $FILE"
echo "  from $URL"
echo "  into $APP_SUPPORT"
echo "(This is the best small open-source dictation + translation model stack.)"
echo

TMP="$(mktemp)"
if command -v curl >/dev/null; then
  curl -L --fail --progress-bar -o "$TMP" "$URL"
elif command -v wget >/dev/null; then
  wget -O "$TMP" "$URL"
else
  echo "Need curl or wget"
  exit 1
fi

mv "$TMP" "$APP_SUPPORT/$FILE"
ln -sf "$APP_SUPPORT/$FILE" "$PROJECT_MODELS/$FILE" 2>/dev/null || cp "$APP_SUPPORT/$FILE" "$PROJECT_MODELS/$FILE"

SIZE=$(du -h "$APP_SUPPORT/$FILE" | awk '{print $1}')
echo
echo "✓ Saved $FILE ($SIZE)"
echo "  App path:     $APP_SUPPORT/$FILE"
echo "  Project path: $PROJECT_MODELS/$FILE"
echo
echo "Default recommendation: small (multilingual + translate-to-English)"
