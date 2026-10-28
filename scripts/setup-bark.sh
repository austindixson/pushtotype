#!/usr/bin/env bash
# Download one Underdog Bark model and install the MLX runtime. Weights are not committed.
set -euo pipefail

[[ "$(uname -m)" == "arm64" ]] || { echo "Bark requires Apple silicon."; exit 1; }
: "${BARK_DIR:?}"
: "${BARK_REPO:?}"
: "${BARK_REVISION:?}"
: "${BARK_SHA256:?}"
: "${BARK_URL:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="${HOME}/Library/Application Support/PushToType"
VENV="$SUPPORT/bark-venv"
if [[ -f "$HERE/bark_worker.py" ]]; then
  WORKER="$HERE/bark_worker.py"
else
  WORKER="$ROOT/Resources/bark_worker.py"
fi

python3 -m venv "$VENV"
"$VENV/bin/pip" install -U pip
"$VENV/bin/pip" install \
  'mlx==0.32.2' \
  'mlx-audio==0.5.3' \
  'constriction==0.5.0' \
  'numpy==2.4.6' \
  'soundfile==0.14.0' \
  'soxr==1.1.0'
export BARK_DIR BARK_REPO BARK_REVISION BARK_SHA256 BARK_URL
"$VENV/bin/python" "$WORKER" --download
echo "Bark weights ready in $BARK_DIR"
