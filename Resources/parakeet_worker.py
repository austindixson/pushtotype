#!/usr/bin/env python3
"""
Persistent Parakeet ASR worker for PushToType.
Loads the ONNX model once, then reads JSON lines from stdin:

  {"cmd":"ping"}
  {"cmd":"transcribe","path":"/path/to/audio.wav"}
  {"cmd":"quit"}

Responds with one JSON object per line:
  {"ok":true,"text":"..."}
  {"ok":false,"error":"..."}
"""
from __future__ import annotations

import json
import os
import sys
import traceback


def main() -> int:
    model_name = os.environ.get("PARAKEET_MODEL", "nemo-parakeet-tdt-0.6b-v2")
    model_path = os.environ.get("PARAKEET_MODEL_PATH", "")
    quant = os.environ.get("PARAKEET_QUANT", "int8") or None
    if quant in ("", "none", "fp32"):
        quant = None

    # Force unbuffered line IO
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
    sys.stderr.reconfigure(line_buffering=True)  # type: ignore[attr-defined]

    try:
        import onnx_asr
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"onnx_asr import failed: {e}"}), flush=True)
        return 1

    try:
        # Prefer HF cache / hub when no local ONNX files present
        if model_path and any(f.endswith(".onnx") for f in os.listdir(model_path) if os.path.isdir(model_path)):
            if quant:
                model = onnx_asr.load_model(model_name, model_path, quantization=quant)
            else:
                model = onnx_asr.load_model(model_name, model_path)
        else:
            if quant:
                model = onnx_asr.load_model(model_name, quantization=quant)
            else:
                model = onnx_asr.load_model(model_name)
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"model load failed: {e}"}), flush=True)
        return 1

    print(json.dumps({"ok": True, "event": "ready", "model": model_name, "quant": quant or "fp32"}), flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            print(json.dumps({"ok": False, "error": f"bad json: {e}"}), flush=True)
            continue

        cmd = req.get("cmd", "")
        if cmd == "quit":
            print(json.dumps({"ok": True, "event": "bye"}), flush=True)
            return 0
        if cmd == "ping":
            print(json.dumps({"ok": True, "event": "pong"}), flush=True)
            continue
        if cmd != "transcribe":
            print(json.dumps({"ok": False, "error": f"unknown cmd: {cmd}"}), flush=True)
            continue

        path = req.get("path", "")
        if not path or not os.path.isfile(path):
            print(json.dumps({"ok": False, "error": f"missing audio: {path}"}), flush=True)
            continue

        try:
            text = model.recognize(path)
            # Some adapters return list / object
            if isinstance(text, (list, tuple)):
                text = text[0] if text else ""
            if hasattr(text, "text"):
                text = getattr(text, "text") or ""
            text = str(text).strip()
            print(json.dumps({"ok": True, "text": text}), flush=True)
        except Exception as e:
            print(
                json.dumps({"ok": False, "error": str(e), "trace": traceback.format_exc()[-800:]}),
                flush=True,
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
