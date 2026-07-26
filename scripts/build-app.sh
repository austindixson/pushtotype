#!/usr/bin/env bash
# Build a local-only NotFluid.app (ad-hoc signed — no notarization / Gatekeeper drama).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/NotFluid.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "→ Building NotFluid (release)…"
swift build -c release --product NotFluid

BIN="$(swift build -c release --show-bin-path)/NotFluid"
if [[ ! -x "$BIN" ]]; then
  echo "Build failed: binary not found at $BIN"
  exit 1
fi

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/NotFluid"
chmod +x "$MACOS/NotFluid"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
# Do NOT embed entitlements that request mic/automation at sign time —
# they can make Gatekeeper treat a personal tool like malware.
# Permissions are still requested at runtime via normal system prompts.

# Ad-hoc sign only (personal machine). Stable notarized Developer ID is overkill here.
echo "→ Ad-hoc codesign (local use)…"
codesign --force --deep --sign - "$APP"

# Strip Gatekeeper quarantine / download flags so macOS doesn't trash it on open
xattr -cr "$APP" 2>/dev/null || true

echo "→ Verifying…"
codesign -dv "$APP" 2>&1 | head -8
ls -la "$MACOS/NotFluid"
file "$MACOS/NotFluid"

echo
echo "✓ Built: $APP"
echo
echo "Launch with:"
echo "  ./scripts/run.sh"
echo
echo "If macOS still blocks it:"
echo "  1) Right-click NotFluid.app → Open → Open"
echo "  2) Or System Settings → Privacy & Security → Open Anyway"
echo "  3) Then enable Accessibility + Microphone for NotFluid"
echo
echo "Hotkey: hold Right ⌥ to dictate"
