#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OVERLAY="$(node scripts/prepare-swift-overlay.mjs releases/.swift-compat)"
COMPAT=(-module-name HabitCounter)
if [[ -n "$OVERLAY" ]]; then COMPAT+=(-vfsoverlay "$OVERLAY"); fi
swiftc -swift-version 5 -parse-as-library "${COMPAT[@]}" -module-cache-path releases/.swift-module-cache \
  -framework SwiftUI -framework WidgetKit -framework ServiceManagement -framework WebKit -framework UniformTypeIdentifiers -framework UserNotifications -framework ApplicationServices -lsqlite3 -lz \
  Apple/Tests/ScreenTimeChecks.swift Apple/Shared/{ScreenTimeReader,IPhoneScreenTime,PhoneScreenTimeController,SettingsScreenTime,SettingsHistory,WebHost,NativeStore,DesktopTools,DesktopWidget,WidgetSummary,WidgetPublisher,Pomodoro}.swift \
  -o releases/ScreenTimeChecks
releases/ScreenTimeChecks
