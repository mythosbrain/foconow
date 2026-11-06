#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---unsigned}"
TEAM="${2:-}"
case "$MODE" in
  --unsigned|--signed) ;;
  *) echo 'Usage: scripts/build-ios.sh [--unsigned | --signed TEAM_ID]' >&2; exit 2 ;;
esac
if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'Cannot build an IPA: full Xcode and the iOS platform SDK are not installed or selected.' >&2
  echo 'Install Xcode from the Mac App Store, open it to finish setup, then rerun this script.' >&2
  echo 'If Xcode is installed elsewhere, set DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer.' >&2
  exit 1
fi
SDK_CHECK="$(xcrun --sdk iphoneos --show-sdk-path 2>&1)" || {
  echo "$SDK_CHECK" >&2
  echo 'Open Xcode and complete its license and initial setup, including the iOS platform SDK.' >&2
  exit 1
}
if [[ "$MODE" == '--signed' && -z "$TEAM" ]]; then
  echo 'Signed builds require your Apple Developer Team ID as the second argument.' >&2
  exit 2
fi
node "$ROOT/scripts/prepare-native-web.mjs"
RELEASES="$ROOT/releases"
DERIVED="$RELEASES/iOSDerivedData"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/habit-counter-ipa.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ARGS=(-project "$ROOT/Apple/HabitCounter.xcodeproj" -scheme HabitCounteriOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED")
if [[ "$MODE" == '--unsigned' ]]; then
  xcodebuild "${ARGS[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  OUTPUT="$RELEASES/Habit-Counter-iPhone-unsigned.ipa"
else
  xcodebuild "${ARGS[@]}" "DEVELOPMENT_TEAM=$TEAM" -allowProvisioningUpdates build
  OUTPUT="$RELEASES/Habit-Counter-iPhone-development.ipa"
fi
PRODUCT="$DERIVED/Build/Products/Release-iphoneos/Habit Counter.app"
if [[ ! -d "$PRODUCT" ]]; then
  echo "Build did not produce the expected iPhone app: $PRODUCT" >&2
  exit 1
fi
if [[ ! -d "$PRODUCT/PlugIns/HabitFocusMonitor.appex" ]]; then
  echo 'The Device Activity monitoring extension is missing from the build.' >&2
  exit 1
fi
if [[ "$MODE" == '--signed' ]]; then
  python3 "$ROOT/scripts/verify-screen-time-signing.py" "$PRODUCT"
fi
mkdir -p "$STAGING/Payload"
ditto "$PRODUCT" "$STAGING/Payload/Habit Counter.app"
ditto -c -k --keepParent "$STAGING/Payload" "$OUTPUT"
echo "IPA: $OUTPUT"
if [[ "$MODE" == '--unsigned' ]]; then
  echo 'This IPA requires Family Controls and matching App Group profiles for BOTH app and monitor extension. Ordinary re-signing is insufficient.'
  echo 'This release saves locally. Device sync is not enabled.'
else
  echo 'This development IPA installs only on devices included in the provisioning profile.'
fi
