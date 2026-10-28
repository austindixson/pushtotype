#!/usr/bin/env bash
# Install Parakeet (onnx-asr) and pin the int8 ONNX files to a Hugging Face revision.
set -euo pipefail

SUPPORT="${HOME}/Library/Application Support/PushToType"
VENV="$SUPPORT/parakeet-venv"
MODELS="$SUPPORT/Models/parakeet"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$HERE/parakeet_worker.py" ]]; then
  WORKER_SRC="$HERE/parakeet_worker.py"
else
  WORKER_SRC="$ROOT/Resources/parakeet_worker.py"
fi

# Revisions and checksums match ParakeetModel in Sources/PushToTypeSupport/EngineCatalog.swift.
V2_REPO="istupakov/parakeet-tdt-0.6b-v2-onnx"
V2_REV="0bbb45a3365852604aef28b538a8f066f4ccaa85"
V3_REPO="istupakov/parakeet-tdt-0.6b-v3-onnx"
V3_REV="8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce"

mkdir -p "$SUPPORT" "$MODELS"
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -U pip wheel setuptools >/dev/null
pip install -U 'onnx-asr[cpu,hub]' 'huggingface_hub'

if [[ -f "$WORKER_SRC" ]]; then
  cp "$WORKER_SRC" "$SUPPORT/parakeet_worker.py"
  chmod +x "$SUPPORT/parakeet_worker.py"
fi

export HF_HOME="${HF_HOME:-$SUPPORT/hf-cache}"
mkdir -p "$HF_HOME"
export PYTHONUNBUFFERED=1

download_model() {
  local repo="$1" rev="$2" dest="$3"
  shift 3
  echo "→ $repo @ $rev"
  "$VENV/bin/python" - "$repo" "$rev" "$dest" "$@" <<'PY'
import hashlib, shutil, sys
from pathlib import Path
from huggingface_hub import hf_hub_download
repo, rev, dest, *rows = sys.argv[1:]
out = Path(dest)
out.mkdir(parents=True, exist_ok=True)
for row in rows:
    name, expected = row.split("=", 1)
    path = Path(hf_hub_download(repo_id=repo, filename=name, revision=rev))
    target = out / name
    shutil.copyfile(path, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != expected:
        target.unlink(missing_ok=True)
        raise SystemExit(f"checksum mismatch for {name}")
    print(f"  {name} {target.stat().st_size} bytes ok")
(out / ".ready").write_text(rev + "\n", encoding="utf-8")
PY
}

download_model "$V2_REPO" "$V2_REV" "$MODELS/tdt-0.6b-v2-int8" \
  "encoder-model.int8.onnx=3e0581fda6ab843888b51e56d7ee78b6d5bc3237ec113af1f732d1d5286aa155" \
  "decoder_joint-model.int8.onnx=a449f49acd68979d418651dd2dcb737cc0f1bf0225e009e29ee326354edbf7d3" \
  "nemo128.onnx=a9fde1486ebfcc08f328d75ad4610c67835fea58c73ba57e3209a6f6cf019e9f" \
  "config.json=skip"

# config.json is tiny and not pinned above; fetch it without a weight checksum.
"$VENV/bin/python" - <<PY
from huggingface_hub import hf_hub_download
from pathlib import Path
import shutil
src = Path(hf_hub_download(repo_id="$V2_REPO", filename="config.json", revision="$V2_REV"))
shutil.copyfile(src, Path("$MODELS/tdt-0.6b-v2-int8/config.json"))
src = Path(hf_hub_download(repo_id="$V3_REPO", filename="config.json", revision="$V3_REV"))
Path("$MODELS/tdt-0.6b-v3-int8").mkdir(parents=True, exist_ok=True)
shutil.copyfile(src, Path("$MODELS/tdt-0.6b-v3-int8/config.json"))
PY

download_model "$V3_REPO" "$V3_REV" "$MODELS/tdt-0.6b-v3-int8" \
  "encoder-model.int8.onnx=6139d2fa7e1b086097b277c7149725edbab89cc7c7ae64b23c741be4055aff09" \
  "decoder_joint-model.int8.onnx=eea7483ee3d1a30375daedc8ed83e3960c91b098812127a0d99d1c8977667a70" \
  "nemo128.onnx=a9fde1486ebfcc08f328d75ad4610c67835fea58c73ba57e3209a6f6cf019e9f"

echo "Parakeet runtime ready"
echo "  v2 int8 about 661 MB · v3 int8 about 671 MB"
