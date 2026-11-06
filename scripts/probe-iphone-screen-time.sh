#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p releases verification
OVERLAY="$(node scripts/prepare-swift-overlay.mjs releases/.swift-compat)"
COMPAT=(-module-name HabitCounter)
if [[ -n "$OVERLAY" ]]; then COMPAT+=(-vfsoverlay "$OVERLAY"); fi
swiftc -swift-version 5 -parse-as-library "${COMPAT[@]}" -module-cache-path releases/.swift-module-cache \
  Apple/Shared/{ScreenTimeReader,IPhoneScreenTime}.swift Apple/Tests/ScreenTimeProbe.swift -lsqlite3 -lz -o releases/ScreenTimeProbe
releases/ScreenTimeProbe
