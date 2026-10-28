#!/usr/bin/env python3
"""Underdog Bark worker. Weights stay out of git and are checked before load.

Stdout is only newline-delimited JSON. MLX logs go to stderr.
"""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

COMPANIONS = (
    "bark_mlx.py",
    "bark_loader.py",
    "mlx/config.json",
    "mlx/tokenizer.model",
    "mlx/tokenizer.vocab",
    "mlx/vocab.txt",
)


def emit(value: dict) -> None:
    print(json.dumps(value), flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    temporary = dest.with_suffix(dest.suffix + ".partial")
    request = urllib.request.Request(url, headers={"User-Agent": "PushToType/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as out:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)
    temporary.replace(dest)


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing {name}")
    return value


def helper_checksums() -> dict:
    raw = os.environ.get("BARK_HELPERS", "").strip()
    if not raw:
        raise RuntimeError("Bark loader checksums were not provided")
    parsed = json.loads(raw)
    if not isinstance(parsed, dict) or "bark_mlx.py" not in parsed or "bark_loader.py" not in parsed:
        raise RuntimeError("Bark loader checksums are incomplete")
    return {str(name): str(digest) for name, digest in parsed.items()}


def ensure_named(root: Path, base: str, name: str, expected: str | None) -> None:
    dest = root / name
    if expected and dest.exists() and sha256(dest) == expected:
        return
    if expected is None and dest.exists() and dest.stat().st_size > 0:
        return
    download(f"{base}/{name}", dest)
    if expected and sha256(dest) != expected:
        dest.unlink(missing_ok=True)
        raise RuntimeError(f"{name} checksum did not match the pinned SHA-256")


def ensure_files(root: Path) -> Path:
    repo = require("BARK_REPO")
    revision = require("BARK_REVISION")
    expected = require("BARK_SHA256")
    weight_url = require("BARK_URL")
    helpers = helper_checksums()
    weight = root / "model.bark"
    if not weight.exists() or sha256(weight) != expected:
        download(weight_url, weight)
    got = sha256(weight)
    if got != expected:
        weight.unlink(missing_ok=True)
        raise RuntimeError("Bark weight checksum did not match the pinned SHA-256")
    base = f"https://huggingface.co/{repo}/resolve/{revision}"
    for relative in COMPANIONS:
        ensure_named(root, base, relative, helpers.get(relative))
    return weight


def load_model(root: Path, weight: Path):
    sys.path.insert(0, str(root))
    import bark_mlx  # noqa: WPS433

    return bark_mlx.load_model(str(weight), bits=16, cache_dir=str(root / "mlx-cache-fp16"))


def transcribe(model, path: str) -> str:
    import bark_mlx
    import soundfile as sf

    wave, sample_rate = sf.read(path, dtype="float32", always_2d=True)
    return bark_mlx.transcribe(model, wave.mean(axis=1), sample_rate)


def main() -> int:
    download_only = "--download" in sys.argv
    try:
        root = Path(require("BARK_DIR"))
        root.mkdir(parents=True, exist_ok=True)
        weight = ensure_files(root)
        if download_only:
            emit({"ok": True, "event": "downloaded", "bytes": weight.stat().st_size})
            return 0
        with contextlib.redirect_stdout(sys.stderr):
            model = load_model(root, weight)
        emit({"ok": True, "event": "ready"})
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
                if request.get("cmd") != "transcribe":
                    raise ValueError("unknown command")
                with contextlib.redirect_stdout(sys.stderr):
                    text = transcribe(model, request["path"])
                emit({"ok": True, "text": text})
            except Exception as error:  # noqa: BLE001
                emit({"ok": False, "error": str(error)})
        return 0
    except Exception as error:  # noqa: BLE001
        emit({"ok": False, "error": str(error)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
