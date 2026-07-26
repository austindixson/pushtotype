#!/usr/bin/env bash
# Build (if needed) and launch NotFluid without Gatekeeper trashing it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/NotFluid.app"
BIN="$APP/Contents/MacOS/NotFluid"

if [[ ! -x "$BIN" ]]; then
  echo "App missing — building…"
  "$ROOT/scripts/build-app.sh"
fi

# Always clear quarantine (Gatekeeper marks apps and can auto-trash them)
xattr -cr "$APP" 2>/dev/null || true

# Re-affirm ad-hoc signature if something stripped it
if ! codesign -v "$APP" 2>/dev/null; then
  codesign --force --deep --sign - "$APP"
  xattr -cr "$APP" 2>/dev/null || true
fi

# Kill prior instance
pkill -x NotFluid 2>/dev/null || true
sleep 0.2

echo "→ Launching $APP"
# Prefer direct exec (avoids some open(1) Gatekeeper paths)
"$BIN" &
PID=$!
sleep 0.6

if kill -0 "$PID" 2>/dev/null || pgrep -x NotFluid >/dev/null; then
  echo "✓ Running (menu bar mic icon). PID=$(pgrep -x NotFluid | tr '\n' ' ')"
  echo "  Hold Right ⌥ to dictate · Quit from the menu panel"
else
  echo "Direct launch failed — trying open(1)…"
  open "$APP" || true
  sleep 0.8
  if pgrep -x NotFluid >/dev/null; then
    echo "✓ Running via open"
  else
    echo "✗ macOS blocked the app."
    echo "  Right-click dist/NotFluid.app → Open → Open"
    echo "  Then: System Settings → Privacy & Security → allow NotFluid if prompted"
    exit 1
  fi
fi
