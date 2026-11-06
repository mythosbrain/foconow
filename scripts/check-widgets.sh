#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$(node "$ROOT/scripts/prepare-swift-overlay.mjs" "$ROOT/releases/.swift-compat")"
COMPAT=(-module-name HabitCounterWidgetChecks)
if [[ -n "$OVERLAY" ]]; then COMPAT+=(-vfsoverlay "$OVERLAY"); fi
swiftc -parse-as-library -swift-version 5 "${COMPAT[@]}" -module-cache-path "$ROOT/releases/.swift-module-cache" \
 "$ROOT/Apple/Shared/WidgetSummary.swift" "$ROOT/Apple/Tests/WidgetChecks.swift" -o "$ROOT/releases/WidgetChecks"
"$ROOT/releases/WidgetChecks" "$ROOT/verification/widget-model-checks"
swiftc -parse-as-library -swift-version 5 -D WIDGET_PREVIEW_HARNESS "${COMPAT[@]}" \
 -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx14.0" \
 -module-cache-path "$ROOT/releases/.swift-module-cache" -framework AppKit -framework SwiftUI -framework WidgetKit \
 "$ROOT/Apple/Shared/WidgetSummary.swift" "$ROOT/Apple/Widgets/HabitCounterWidgets.swift" "$ROOT/Apple/Tests/WidgetPreview.swift" -o "$ROOT/releases/WidgetPreview"
