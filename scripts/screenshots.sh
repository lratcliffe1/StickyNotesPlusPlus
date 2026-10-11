#!/usr/bin/env bash
# Builds a Debug copy for the iOS simulator, opens each screenshot state through the
# UITestHarness launch arguments, and saves colour + greyscale PNGs to $OUT (default build/screenshots).
# Needs Xcode. Runs in CI (.github/workflows/screenshots.yml); works locally too.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16}"
OUT="${OUT:-build/screenshots}"
DERIVED="build/sim"
SETTLE_SECONDS="${SETTLE_SECONDS:-5}"

xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -configuration Debug \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME}" -derivedDataPath "$DERIVED" build -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/StickyNote++.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
UDID=$(xcrun simctl list devices available | grep -m1 "    ${DEVICE_NAME} (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "No available simulator named ${DEVICE_NAME}" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

# name | scenario | screen | appearance
SHOTS=(
  "01-home-morning|morning|home|light"
  "02-home-daily|daily|home|light"
  "03-home-empty|empty|home|light"
  "04-calendar|daily|calendar|light"
  "05-settings|daily|settings|light"
  "06-home-morning-dark|morning|home|dark"
)

for shot in "${SHOTS[@]}"; do
  IFS='|' read -r name scenario screen appearance <<<"$shot"
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiScenario "$scenario" -uiScreen "$screen" >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  swift scripts/greyscale.swift "$OUT/$name.png" "$OUT/$name-grey.png"
  echo "captured $name"
done
