#!/usr/bin/env bash
# Builds a Debug copy for the iOS simulator, opens each screenshot state through the
# UITestHarness launch arguments, and saves colour + greyscale PNGs to $OUT (default build/screenshots).
# Needs Xcode. Runs in CI (.github/workflows/screenshots.yml); works locally too.
set -euo pipefail

OUT="${OUT:-build/screenshots}"
# Same path and settings as ios-quality.yml, so both workflows share the cached module cache.
DERIVED="${DERIVED_DATA:-build/DerivedData}"
SETTLE_SECONDS="${SETTLE_SECONDS:-5}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Pick (or create) the simulator and start it booting now: a first boot takes minutes, so it
# overlaps the build instead of following it.
UDID=$("$HERE/ci-simulator.sh" --boot)

xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" COMPILER_INDEX_STORE_ENABLE=NO build -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/StickyNote++.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

# Compile the greyscale filter once rather than interpreting the script for every shot.
GREYSCALE="$DERIVED/greyscale"
swiftc -O "$HERE/greyscale.swift" -o "$GREYSCALE"

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
  "07-banner-missed-yesterday|missedYesterday|home|light"
  "08-banner-missed-twice|missedTwice|home|light"
)

for shot in "${SHOTS[@]}"; do
  IFS='|' read -r name scenario screen appearance <<<"$shot"
  # simctl refuses to replace an active override (it misreports this as "non-ISO date/time"),
  # so clear it first. A clock that still won't set only costs the status bar: warn and go on.
  clock="2:00"  # simctl only accepts 12-hour times here; "14:00" is rejected
  case "$scenario" in morning|missedYesterday) clock="08:15" ;; esac
  xcrun simctl status_bar "$UDID" clear || true
  if ! xcrun simctl status_bar "$UDID" override --time "$clock" \
      --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3; then
    echo "WARNING: status-bar clock not set for $name; its clock is wrong, not the app's time" >&2
  fi
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiScenario "$scenario" -uiScreen "$screen" >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  "$GREYSCALE" "$OUT/$name.png" "$OUT/$name-grey.png"
  echo "captured $name"
done
