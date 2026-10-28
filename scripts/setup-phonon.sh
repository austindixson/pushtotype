#!/usr/bin/env bash
# Install Phonon 2 (fermion-research 0.2.4) into Application Support.
# Weights are downloaded at runtime from FermionResearch/Phonon-2. Not committed.
set -euo pipefail

[[ "$(uname -m)" == "arm64" ]] || { echo "Phonon 2 requires Apple silicon."; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="${HOME}/Library/Application Support/PushToType/phonon-0.2.4"
if [[ -f "$HERE/phonon_worker.py" ]]; then
  WORKER="$HERE/phonon_worker.py"
  REQUIREMENTS="$HERE/phonon-requirements.txt"
else
  WORKER="$ROOT/Resources/phonon_worker.py"
  REQUIREMENTS="$ROOT/Resources/phonon-requirements.txt"
fi

mkdir -p "$SUPPORT"
export UV_PYTHON_INSTALL_DIR="$SUPPORT/python"
export UV_CACHE_DIR="$SUPPORT/uv-cache"
export FERMION_CACHE_DIR="$SUPPORT/models"
export HF_HOME="$SUPPORT/hf-cache"
export PYTHONUNBUFFERED=1
export FERMION_DEVICE=mlx
UV="$SUPPORT/uv-aarch64-apple-darwin/uv"
if [[ ! -x "$UV" ]]; then
  echo "Downloading the local runtime installer…"
  /usr/bin/curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 \
    https://github.com/astral-sh/uv/releases/download/0.12.21/uv-aarch64-apple-darwin.tar.gz \
    --output "$SUPPORT/uv.tar.gz"
  echo "b88bda573e566ef9bced66b155fe0408626fbbc053aee1c30ba686f0728c9447  $SUPPORT/uv.tar.gz" | /usr/bin/shasum -a 256 -c -
  /usr/bin/tar -xzf "$SUPPORT/uv.tar.gz" -C "$SUPPORT"
  rm -f "$SUPPORT/uv.tar.gz"
fi
if [[ ! -x "$SUPPORT/venv/bin/python" ]]; then
  "$UV" venv --python 3.12.13 --managed-python "$SUPPORT/venv"
fi
echo "Installing Phonon 2 runtime (164 MB model; Python packages are extra)…"
"$UV" pip install --python "$SUPPORT/venv/bin/python" --requirement "$REQUIREMENTS"
"$SUPPORT/venv/bin/python" "$WORKER" --install
echo "Phonon 2 is ready."
