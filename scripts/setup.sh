#!/usr/bin/env bash
# One-shot setup for n0tfluid
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "═══ n0tfluid setup ═══"
echo

if ! command -v brew >/dev/null; then
  echo "Homebrew not found. Install from https://brew.sh"
  exit 1
fi

if ! command -v whisper-cli >/dev/null && ! command -v whisper-cpp >/dev/null && [[ ! -x /opt/homebrew/bin/whisper-cli ]]; then
  echo "→ Installing whisper-cpp (Metal-accelerated Whisper)…"
  brew install whisper-cpp
else
  echo "✓ whisper.cpp already installed"
fi

echo "→ Downloading Whisper Small (best small open model for dictation + translation)…"
"$ROOT/scripts/download-model.sh" small

echo "→ Building app…"
"$ROOT/scripts/build-app.sh"

echo
echo "═══ Ready ═══"
echo "Launch: open \"$ROOT/dist/NotFluid.app\""
echo "Then grant Microphone + Accessibility when prompted."
echo "Hold Right ⌥ to dictate. Switch to Translate mode for any-language → English."
