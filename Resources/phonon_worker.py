"""Local Phonon 2 bridge.

Weights: Fermion Research Phonon 2, CC-BY-4.0, downloaded by fermion-research.
Runtime: fermion-research 0.2.4, Apache-2.0. See phonon-notices.txt.
Stdout is only newline-delimited JSON.
"""
import contextlib
import json
import os
from pathlib import Path
import sys


def emit(value):
    print(json.dumps(value), flush=True)


def load(install=False):
    from fermion.transcribe import _resolve
    from fermion._speech import backends, fetch
    repo, key, pin, _ = _resolve("phonon-2")
    engine = backends.resolve("PushToType Phonon 2")
    if install:
        directory = fetch.ensure(repo, key, pin)
    else:
        directory = fetch.profile_dir(repo, pin["unpack_dir"])
        if not fetch.is_model_dir(directory):
            raise RuntimeError("Download Phonon 2 in Settings first.")
    return backends.load(engine, directory, profile=key, backend=pin["backend"], quiet=True)


def transcript(speech, path):
    result = speech.transcribe_detailed(path)
    if result.truncated:
        raise RuntimeError("Phonon 2 could not finish that recording. Try a shorter take or Whisper.")
    text, _, _ = result.triple()
    return text.strip()


def main():
    install = "--install" in sys.argv
    if not install:
        os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["FERMION_DEVICE"] = "mlx"
    try:
        with contextlib.redirect_stdout(sys.stderr):
            speech = load(install=install)
        if install:
            marker = Path(os.environ["FERMION_CACHE_DIR"]) / "ready-0.2.4"
            marker.parent.mkdir(parents=True, exist_ok=True)
            marker.write_text("phonon-2\n")
            return
        emit({"ok": True, "event": "ready"})
        for line in sys.stdin:
            try:
                request = json.loads(line)
                if request.get("cmd") != "transcribe":
                    raise ValueError("Unknown Phonon command")
                with contextlib.redirect_stdout(sys.stderr):
                    text = transcript(speech, request["path"])
                emit({"ok": True, "text": text})
            except Exception as error:
                emit({"ok": False, "error": str(error)})
    except (Exception, SystemExit) as error:
        emit({"ok": False, "error": str(error)})
        raise SystemExit(1)


if __name__ == "__main__":
    main()
