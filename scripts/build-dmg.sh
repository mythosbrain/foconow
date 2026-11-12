#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/releases/FocoNow.app"
VENV="${FOCONOW_DMG_VENV:-$ROOT/releases/.dmg-tools}"
ART="$ROOT/releases/.dmg-art"
if [[ ! -d "$APP" ]]; then
  echo 'Build the app first: bash scripts/build-mac.sh' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -r "$ROOT/scripts/dmg/requirements.txt"
fi
mkdir -p "$ART"
swiftc -module-cache-path "$ROOT/releases/.swift-module-cache" "$ROOT/scripts/dmg/background.swift" -o "$ART/render"
"$ART/render" "$ART"
# Bind the optional first-launch helper to this exact signed app build.
CDHASH="$(codesign -d --verbose=4 "$APP" 2>&1 | sed -n 's/^CDHash=//p')"
[[ "$CDHASH" =~ ^[0-9a-f]{40}$ ]] || { echo 'Could not determine app code identity' >&2; exit 1; }
sed "s/@CDHASH@/$CDHASH/" "$ROOT/scripts/installer/Open-FocoNow.command.in" > "$ART/Open FocoNow.command"
chmod 755 "$ART/Open FocoNow.command"
cp "$ROOT/scripts/installer/First-launch.txt" "$ART/First launch.txt"
SUFFIX="${FOCONOW_DMG_SUFFIX:-}"
[[ "$SUFFIX" =~ ^[a-zA-Z0-9-]*$ ]] || { echo 'Invalid DMG suffix' >&2; exit 1; }
DMG="$ROOT/releases/FocoNow-Mac-v$VERSION$SUFFIX.dmg"
"$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg/settings.py" "-Dapp=$APP" "-Dbackground=$ART/background.png" "-Dhelper=$ART/Open FocoNow.command" "-Dguide=$ART/First launch.txt" FocoNow "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT/releases" && shasum -a 256 "FocoNow-Mac-v$VERSION$SUFFIX.dmg" > "FocoNow-Mac-v$VERSION$SUFFIX.dmg.sha256")
echo "Installer: $DMG"
