#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT="${1:-$ROOT/releases/FocoNow.app/Contents/PlugIns/HabitCounterWidgets.appex}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OVERLAY="$(node "$ROOT/scripts/prepare-swift-overlay.mjs" "$ROOT/releases/.swift-compat")"
COMPAT=(-module-name HabitCounterWidgets)
if [[ -n "$OVERLAY" ]]; then COMPAT+=(-vfsoverlay "$OVERLAY"); fi
mkdir -p "$EXT/Contents/MacOS"
swiftc -parse-as-library -swift-version 5 -O -application-extension \
  -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" "${COMPAT[@]}" \
  -module-cache-path "$ROOT/releases/.swift-module-cache" \
  -framework SwiftUI -framework WidgetKit \
  "$ROOT/Apple/Shared/WidgetSummary.swift" "$ROOT/Apple/Widgets/HabitCounterWidgets.swift" \
  -Xlinker -e -Xlinker _NSExtensionMain -o "$EXT/Contents/MacOS/HabitCounterWidgets"
cp "$ROOT/Apple/Config/Widgets-Info.plist" "$EXT/Contents/Info.plist"
codesign --force --sign - --entitlements "$ROOT/Apple/Config/Widgets.entitlements" "$EXT"
codesign --verify --strict "$EXT"
echo "Widget extension: $EXT"
