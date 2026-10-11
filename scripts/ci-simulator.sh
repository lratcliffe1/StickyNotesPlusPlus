#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator (DEVICE_NAME, default "iPhone 16"), creating one if
# none is listed. Fresh CI runners sometimes list no iPhone at first, which breaks
# `-destination "platform=iOS Simulator,name=..."`; use `-destination id=<UDID>` instead.
#
# It picks the iOS version of the SDK this Xcode builds with (SIM_OS overrides, e.g. SIM_OS=26.2), and
# falls back to the newest runtime listed. A `name=` destination would take the newest runtime, which
# changes whenever the runner image adds one.
#
#   UDID=$(scripts/ci-simulator.sh)
#
# Used by ios-quality.yml and scripts/screenshots.sh. Boot the device after the build
# (`xcrun simctl bootstatus "$UDID" -b`), not during it: on the 3-core CI runners a boot in the
# background slowed the build several-fold and saved nothing overall.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16}"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.$(echo "$DEVICE_NAME" | tr ' ' '-')"

SIM_OS="${SIM_OS:-$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || true)}"

# awk reads all of simctl's output (no early-exit pipe to trip pipefail). Sections are listed oldest
# runtime first; "iPhone 16 (" excludes "iPhone 16 Pro". Prints the SIM_OS match, else the newest.
find_udid() {
  xcrun simctl list devices available \
    | awk -v want="    ${DEVICE_NAME} (" -v os="-- iOS ${SIM_OS} --" '
        /^-- / { ios = ($0 ~ /^-- iOS /); exact = ($0 == os) }
        ios && index($0, want) == 1 { last = $0; if (exact) match_os = $0 }
        END { if (match_os != "") print match_os; else if (last != "") print last }' \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

# Runtime lines end with the identifier: "iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5".
find_runtime() {
  xcrun simctl list runtimes available \
    | awk -v os="iOS ${SIM_OS} (" '
        /^iOS / { last = $NF; if (index($0, os) == 1) exact = $NF }
        END { if (exact != "") print exact; else print last }'
}

UDID=""
for attempt in 1 2 3; do
  UDID=$(find_udid)
  [ -n "$UDID" ] && break
  RUNTIME=$(find_runtime)
  if [ -n "$RUNTIME" ]; then
    echo "Creating ${DEVICE_NAME} on ${RUNTIME}" >&2
    UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME") && break
  fi
  echo "No ${DEVICE_NAME} simulator yet (attempt ${attempt}); waiting for CoreSimulator" >&2
  sleep 10
done
[ -n "$UDID" ] || { echo "No simulator available for ${DEVICE_NAME}" >&2; exit 1; }

xcrun simctl list devices | grep -F "$UDID" | sed 's/^ */Simulator: /' >&2 || true

echo "$UDID"
