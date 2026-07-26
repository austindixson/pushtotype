#!/usr/bin/env bash
# Sign dist/NotFluid.app with Apple Development so Accessibility can persist across rebuilds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/NotFluid.app"

if [[ ! -d "$APP" ]]; then
  echo "Build first: ./scripts/build-app.sh"
  exit 1
fi

IDENTITY="${NOTFLUID_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p' | head -1 || true)
fi

if [[ -z "$IDENTITY" ]]; then
  echo "No Apple Development identity found. Using ad-hoc."
  codesign --force --deep --sign - "$APP"
else
  echo "Signing with $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" \
    --entitlements "$ROOT/Resources/NotFluid.entitlements" \
    "$APP" || codesign --force --deep --sign "$IDENTITY" "$APP"
fi

xattr -cr "$APP" 2>/dev/null || true
codesign -dv "$APP" 2>&1 | head -12
echo
echo "Then: System Settings → Privacy → Accessibility → enable NotFluid"
echo "Launch: ./scripts/run.sh"
