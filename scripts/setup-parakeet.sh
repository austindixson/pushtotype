#!/usr/bin/env bash
# Install Parakeet (onnx-asr) runtime for PushToType into Application Support.
set -euo pipefail

SUPPORT="${HOME}/Library/Application Support/NotFluid"
VENV="$SUPPORT/parakeet-venv"
MODELS="$SUPPORT/Models/parakeet"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKER_SRC="$ROOT/Resources/parakeet_worker.py"
# When script is copied into the app bundle Resources/
if [[ ! -f "$WORKER_SRC" ]]; then
  WORKER_SRC="$(cd "$(dirname "$0")" && pwd)/parakeet_worker.py"
fi

mkdir -p "$SUPPORT" "$MODELS"

echo "→ Creating venv at $VENV"
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -U pip wheel setuptools >/dev/null
echo "→ Installing onnx-asr (CPU + HF hub)…"
pip install -U 'onnx-asr[cpu,hub]'

if [[ -f "$WORKER_SRC" ]]; then
  cp "$WORKER_SRC" "$SUPPORT/parakeet_worker.py"
  chmod +x "$SUPPORT/parakeet_worker.py"
  echo "→ Worker → $SUPPORT/parakeet_worker.py"
else
  echo "WARNING: parakeet_worker.py not found at $WORKER_SRC"
fi

export HF_HOME="${HF_HOME:-$SUPPORT/hf-cache}"
mkdir -p "$HF_HOME"
export PYTHONUNBUFFERED=1

echo "→ Downloading English Parakeet TDT 0.6B v2 (int8) into HF cache…"
"$VENV/bin/python" - <<'PY'
import onnx_asr
print("loading nemo-parakeet-tdt-0.6b-v2 int8…")
m = onnx_asr.load_model("nemo-parakeet-tdt-0.6b-v2", quantization="int8")
print("v2 ready")
# Touch a marker so the app knows install completed
from pathlib import Path
p = Path.home() / "Library/Application Support/NotFluid/Models/parakeet/tdt-0.6b-v2-int8"
p.mkdir(parents=True, exist_ok=True)
(p / ".ready").write_text("nemo-parakeet-tdt-0.6b-v2\nint8\n", encoding="utf-8")
print("marker", p / ".ready")
PY

echo "→ Downloading Multilingual Parakeet TDT 0.6B v3 (int8)…"
"$VENV/bin/python" - <<'PY'
import onnx_asr
from pathlib import Path
print("loading nemo-parakeet-tdt-0.6b-v3 int8…")
m = onnx_asr.load_model("nemo-parakeet-tdt-0.6b-v3", quantization="int8")
print("v3 ready")
p = Path.home() / "Library/Application Support/NotFluid/Models/parakeet/tdt-0.6b-v3-int8"
p.mkdir(parents=True, exist_ok=True)
(p / ".ready").write_text("nemo-parakeet-tdt-0.6b-v3\nint8\n", encoding="utf-8")
print("marker", p / ".ready")
PY

# Quick smoke: empty short wav skip — just ping worker ready path
echo
echo "✓ Parakeet runtime ready"
echo "  Python: $VENV/bin/python"
echo "  HF cache: $HF_HOME"
echo "  Restart PushToType → Engine → Parakeet"
