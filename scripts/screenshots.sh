#!/usr/bin/env bash
# Builds a Debug copy for the iOS simulator, opens each screenshot state through the
# UITestHarness launch arguments, and saves colour + greyscale PNGs to $OUT (default build/screenshots).
# Needs Xcode. Runs in CI (.github/workflows/screenshots.yml); works locally too.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16}"
OUT="${OUT:-build/screenshots}"
DERIVED="build/sim"
SETTLE_SECONDS="${SETTLE_SECONDS:-5}"

# A generic destination needs no simulator to exist yet (fresh CI runners can list none at first).
xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -configuration Debug \
  -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" build -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/StickyNote++.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

# awk reads all of simctl's output (no early-exit pipe to trip pipefail) and prints the first match.
find_udid() {
  xcrun simctl list devices available \
    | awk -v want="    ${DEVICE_NAME} (" 'index($0, want) == 1 && !found { print; found = 1 }' \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}
UDID=$(find_udid)
if [ -z "$UDID" ]; then
  # No such simulator: create one on the newest installed iOS runtime.
  RUNTIME=$(xcrun simctl list runtimes available | grep -E "^iOS " | tail -1 | sed -E 's/.* - (com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+).*/\1/')
  DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.$(echo "$DEVICE_NAME" | tr ' ' '-')"
  echo "Creating ${DEVICE_NAME} on ${RUNTIME}"
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi
[ -n "$UDID" ] || { echo "No simulator available for ${DEVICE_NAME}" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

# name | scenario | screen | appearance. The status-bar clock matches each scenario's time.
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
  clock="14:00"
  [ "$scenario" = "morning" ] && clock="08:15"
  xcrun simctl status_bar "$UDID" override --time "$clock" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 || true
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiScenario "$scenario" -uiScreen "$screen" >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  swift scripts/greyscale.swift "$OUT/$name.png" "$OUT/$name-grey.png"
  echo "captured $name"
done
