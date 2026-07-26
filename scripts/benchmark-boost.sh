#!/usr/bin/env bash
# Compare post-STT paths: raw vs punctuation vs Articulate (offline only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Building BoostBenchmark (release)…"
swift build -c release --product BoostBenchmark

BIN="$(swift build -c release --show-bin-path)/BoostBenchmark"
OUT="$ROOT/benchmark-boost-last.txt"
echo
echo "→ Running… (also writing $OUT)"
echo
# Prefer debug if release faults on this toolchain
if ! "$BIN" "$@" | tee "$OUT"; then
  echo "Release binary failed — retrying debug…"
  swift build -c debug --product BoostBenchmark
  DBG="$(swift build -c debug --show-bin-path)/BoostBenchmark"
  "$DBG" "$@" | tee "$OUT"
fi
echo
echo "Saved: $OUT"
