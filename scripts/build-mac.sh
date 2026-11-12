#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASES="$ROOT/releases"
APP="$RELEASES/FocoNow.app"
CACHE="${HABIT_COUNTER_MODULE_CACHE:-$RELEASES/.swift-module-cache}"

if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  echo 'A macOS SDK is required. Install Apple Command Line Tools or Xcode.' >&2
  exit 1
fi
node "$ROOT/scripts/prepare-native-web.mjs"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
OVERLAY="$(node "$ROOT/scripts/prepare-swift-overlay.mjs" "$RELEASES/.swift-compat")"
COMPAT=(-module-name HabitCounter)
if [[ -n "$OVERLAY" ]]; then COMPAT+=(-vfsoverlay "$OVERLAY"); fi
swiftc -parse-as-library -swift-version 5 -O \
  -sdk "$SDK" -target "${ARCH}-apple-macosx13.0" \
  "${COMPAT[@]}" \
  -module-cache-path "$CACHE" \
  -framework SwiftUI -framework WidgetKit -framework ServiceManagement -framework WebKit -framework UniformTypeIdentifiers -framework UserNotifications -framework ApplicationServices -lsqlite3 -lz \
  "$ROOT/Apple/Shared/HabitCounterApp.swift" \
  "$ROOT/Apple/Shared/WebHost.swift" \
  "$ROOT/Apple/Shared/CloudSync.swift" \
  "$ROOT/Apple/Shared/NativeStore.swift" \
  "$ROOT/Apple/Shared/DesktopTools.swift" \
  "$ROOT/Apple/Shared/DesktopWidget.swift" \
  "$ROOT/Apple/Shared/WidgetSummary.swift" \
  "$ROOT/Apple/Shared/WidgetPublisher.swift" \
  "$ROOT/Apple/Shared/Pomodoro.swift" \
  "$ROOT/Apple/Shared/ReminderSupport.swift" \
  "$ROOT/Apple/Shared/ScreenTimeReader.swift" \
  "$ROOT/Apple/Shared/IPhoneScreenTime.swift" \
  "$ROOT/Apple/Shared/PhoneScreenTimeController.swift" \
  "$ROOT/Apple/Shared/SettingsScreenTime.swift" \
  "$ROOT/Apple/Shared/SettingsHistory.swift" \
  -o "$APP/Contents/MacOS/HabitCounter"
cp "$ROOT/Apple/Config/macOS-Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.yassine.habitcounter' "$APP/Contents/Info.plist"
cp -R "$ROOT/Apple/WebContent" "$APP/Contents/Resources/"
cp "$ROOT/Apple/WebContent/FocusFinished.wav" "$ROOT/Apple/WebContent/BreakFinished.wav" "$APP/Contents/Resources/"
cp "$ROOT/Apple/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
bash "$ROOT/scripts/build-widget-extension.sh" "$APP/Contents/PlugIns/HabitCounterWidgets.appex"
# Personal local build: no paid developer certificate or cloud capabilities.
codesign --force --sign - --entitlements "$ROOT/Apple/Config/macOS.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASES/FocoNow-Mac.zip"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
cp "$RELEASES/FocoNow-Mac.zip" "$RELEASES/FocoNow-Mac-v$VERSION.zip"
echo "Built: $APP"
echo "Archive: $RELEASES/FocoNow-Mac.zip"
echo "Versioned archive: $RELEASES/FocoNow-Mac-v$VERSION.zip"
echo 'This Mac release works offline and stores data locally. No paid certificate required.'
