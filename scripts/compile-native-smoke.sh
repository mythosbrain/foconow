#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/releases/HabitCounterNativeSmoke}"
CACHE="${HABIT_COUNTER_MODULE_CACHE:-$ROOT/releases/.swift-module-cache}"
mkdir -p "$(dirname "$OUTPUT")" "$CACHE"
OVERLAY="$(node "$ROOT/scripts/prepare-swift-overlay.mjs" "$ROOT/releases/.swift-compat")"
COMPAT=(-module-name HabitCounter)
if [[ -n "$OVERLAY" ]]; then COMPAT+=(-vfsoverlay "$OVERLAY"); fi
swiftc -parse-as-library -swift-version 5 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" \
  "${COMPAT[@]}" -module-cache-path "$CACHE" \
  -framework SwiftUI -framework WidgetKit -framework ServiceManagement -framework WebKit -framework UniformTypeIdentifiers -framework UserNotifications -framework ApplicationServices -lsqlite3 -lz \
  "${FOCONOW_NATIVE_CHECK_SOURCE:-$ROOT/Apple/Tests/NativeSmoke.swift}" \
  "$ROOT/Apple/Shared/WebHost.swift" \
  "$ROOT/Apple/Shared/NativeStore.swift" \
  "$ROOT/Apple/Shared/DesktopTools.swift" \
  "$ROOT/Apple/Shared/DesktopWidget.swift" \
  "$ROOT/Apple/Shared/WidgetSummary.swift" \
  "$ROOT/Apple/Shared/WidgetPublisher.swift" \
  "$ROOT/Apple/Shared/Pomodoro.swift" \
  "$ROOT/Apple/Shared/ReminderSupport.swift" \
  "$ROOT/Apple/Shared/CompleteBackup.swift" \
  "$ROOT/Apple/Shared/ScreenTimeReader.swift" \
  "$ROOT/Apple/Shared/IPhoneScreenTime.swift" \
  "$ROOT/Apple/Shared/PhoneScreenTimeController.swift" \
  "$ROOT/Apple/Shared/SettingsScreenTime.swift" \
  "$ROOT/Apple/Shared/SettingsHistory.swift" \
  -o "$OUTPUT"
echo "Native smoke harness: $OUTPUT"
