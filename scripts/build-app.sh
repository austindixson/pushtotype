#!/usr/bin/env bash
# Build NotFluid.app. Prefer stable Apple Development signing so Accessibility
# sticks across rebuilds (ad-hoc invalidates TCC every compile).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/NotFluid.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
ENTITLEMENTS="$ROOT/Resources/NotFluid.entitlements"

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
# App icon
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"
  echo "  + AppIcon.icns"
fi
# Parakeet worker + setup script
if [[ -f "$ROOT/Resources/parakeet_worker.py" ]]; then
  cp "$ROOT/Resources/parakeet_worker.py" "$RES/parakeet_worker.py"
  echo "  + parakeet_worker.py"
fi
if [[ -f "$ROOT/scripts/setup-parakeet.sh" ]]; then
  cp "$ROOT/scripts/setup-parakeet.sh" "$RES/setup-parakeet.sh"
  chmod +x "$RES/setup-parakeet.sh"
  echo "  + setup-parakeet.sh"
fi

# Prefer SHA-1 hash (unique). Name alone is ambiguous when two certs match.
resolve_identity() {
  if [[ "${NOTFLUID_ADHOC:-}" == "1" ]]; then
    echo ""
    return
  fi
  if [[ -n "${NOTFLUID_SIGN_IDENTITY:-}" ]]; then
    echo "$NOTFLUID_SIGN_IDENTITY"
    return
  fi
  if [[ -f "$DIST/.sign-identity" ]]; then
    tr -d '[:space:]' < "$DIST/.sign-identity" || true
    return
  fi
  # Prefer second Apple Development cert when first is revoked
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p' \
    | tail -1 || true
}

IDENTITY="$(resolve_identity | head -1)"

sign_ok=0
if [[ -n "$IDENTITY" ]]; then
  echo "→ Stable codesign: $IDENTITY"
  if [[ -f "$ENTITLEMENTS" ]]; then
    if codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$MACOS/NotFluid" 2>/dev/null \
      && codesign --force --deep --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP" 2>/dev/null; then
      sign_ok=1
    fi
  else
    if codesign --force --sign "$IDENTITY" --timestamp=none "$MACOS/NotFluid" 2>/dev/null \
      && codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APP" 2>/dev/null; then
      sign_ok=1
    fi
  fi
  # Reject revoked certs
  if [[ $sign_ok -eq 1 ]]; then
    if spctl -a -vv -t install "$APP" 2>&1 | grep -qi REVOKED; then
      echo "  (identity revoked — trying other hashes)"
      sign_ok=0
    fi
  fi
fi

if [[ $sign_ok -eq 0 ]]; then
  # Try every Apple Development hash
  while IFS= read -r cand; do
    [[ -z "$cand" || "$cand" == "$IDENTITY" ]] && continue
    echo "→ Trying identity ${cand:0:12}…"
    if codesign --force --deep --sign "$cand" --timestamp=none "$APP" 2>/dev/null; then
      if ! spctl -a -vv -t install "$APP" 2>&1 | grep -qi REVOKED; then
        IDENTITY="$cand"
        sign_ok=1
        break
      fi
    fi
  done < <(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p')
fi

if [[ $sign_ok -eq 0 ]]; then
  echo "→ WARNING: Ad-hoc sign (Accessibility resets every rebuild)"
  codesign --force --deep --sign - "$APP"
  IDENTITY=""
else
  mkdir -p "$DIST"
  echo "$IDENTITY" > "$DIST/.sign-identity"
  echo "  Signature STABLE — enable Accessibility ONCE for NotFluid"
fi

xattr -cr "$APP" 2>/dev/null || true

echo "→ Verifying…"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Signature|Identifier|Format' || codesign -dv "$APP" 2>&1 | head -10
ls -la "$MACOS/NotFluid"

echo
echo "✓ Built: $APP"
echo "Launch: ./scripts/run.sh"
echo "Hotkey: hold Right ⌥ to dictate"
