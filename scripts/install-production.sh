#!/usr/bin/env bash
# Production build + install PushToType.app to /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Building production app…"
"$ROOT/scripts/build-app.sh"

SRC="$ROOT/dist/NotFluid.app"
# Ship under the product name users expect
DEST_NAME="PushToType.app"
STAGE="$ROOT/dist/$DEST_NAME"

if [[ ! -d "$SRC" ]]; then
  echo "Build missing: $SRC"
  exit 1
fi

# Stage as PushToType.app (same binary, product branding)
rm -rf "$STAGE"
cp -R "$SRC" "$STAGE"

# Ensure icon is present (build-app should copy it)
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  mkdir -p "$STAGE/Contents/Resources"
  cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT/Resources/Info.plist" ]]; then
  cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"
fi

# Re-sign after resource copy
IDENTITY=""
if [[ -f "$ROOT/dist/.sign-identity" ]]; then
  IDENTITY="$(tr -d '[:space:]' < "$ROOT/dist/.sign-identity")"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p' | tail -1 || true)
fi

if [[ -n "$IDENTITY" ]]; then
  echo "→ Re-signing $DEST_NAME with stable identity…"
  if [[ -f "$ROOT/Resources/NotFluid.entitlements" ]]; then
    codesign --force --deep --sign "$IDENTITY" \
      --entitlements "$ROOT/Resources/NotFluid.entitlements" \
      --timestamp=none "$STAGE" || codesign --force --deep --sign "$IDENTITY" --timestamp=none "$STAGE"
  else
    codesign --force --deep --sign "$IDENTITY" --timestamp=none "$STAGE"
  fi
else
  codesign --force --deep --sign - "$STAGE"
fi
xattr -cr "$STAGE" 2>/dev/null || true

# Install
pkill -x NotFluid 2>/dev/null || true
pkill -x PushToType 2>/dev/null || true
sleep 0.2

INSTALL="/Applications/$DEST_NAME"
echo "→ Installing to $INSTALL"
rm -rf "$INSTALL"
cp -R "$STAGE" "$INSTALL"
xattr -cr "$INSTALL" 2>/dev/null || true

# Touch so Launch Services / Dock pick up icon
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL" 2>/dev/null || true

echo
echo "✓ Installed: $INSTALL"
codesign -dv "$INSTALL" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier' || true
ls -la "$INSTALL/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "(no icon file — check Resources)"
echo
echo "Launch: open -a PushToType"
echo "Or from Spotlight: PushToType"
echo
echo "Enable Accessibility once: System Settings → Privacy → Accessibility → PushToType / NotFluid"
