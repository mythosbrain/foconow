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
cp "$ROOT/scripts/installer/Copy command.html" "$ART/Copy command.html"
swiftc -module-cache-path "$ROOT/releases/.swift-module-cache" "$ROOT/scripts/dmg/copy-icon.swift" -o "$ART/copy-icon"
"$ART/copy-icon" "$ART/Copy command.html" "$ART/copy-icon.png"
SUFFIX="${FOCONOW_DMG_SUFFIX:-}"
[[ "$SUFFIX" =~ ^[a-zA-Z0-9-]*$ ]] || { echo 'Invalid DMG suffix' >&2; exit 1; }
DMG="$ROOT/releases/FocoNow-Mac-v$VERSION$SUFFIX.dmg"
"$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg/settings.py" "-Dapp=$APP" "-Dbackground=$ART/background.png" "-Dpanel=$ART/Copy command.html" FocoNow "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT/releases" && shasum -a 256 "FocoNow-Mac-v$VERSION$SUFFIX.dmg" > "FocoNow-Mac-v$VERSION$SUFFIX.dmg.sha256")
echo "Installer: $DMG"
