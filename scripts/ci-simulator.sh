#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator (DEVICE_NAME, default "iPhone 16"), creating one
# on the newest installed iOS runtime if none is listed. Fresh CI runners sometimes list no iPhone at
# first, which breaks `-destination "platform=iOS Simulator,name=..."`; use `-destination id=<UDID>`.
#
#   UDID=$(scripts/ci-simulator.sh)          # just pick (or create) the device
#   UDID=$(scripts/ci-simulator.sh --boot)   # ...and start booting it in the background
#
# Booting takes minutes on a fresh runner, so start it before the build and wait for it afterwards
# with `xcrun simctl bootstatus "$UDID" -b`. Used by ios-quality.yml and scripts/screenshots.sh.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16}"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.$(echo "$DEVICE_NAME" | tr ' ' '-')"

# awk reads all of simctl's output (no early-exit pipe to trip pipefail) and keeps the last match in
# an iOS section: sections are listed oldest runtime first. "iPhone 16 (" excludes "iPhone 16 Pro".
find_udid() {
  xcrun simctl list devices available \
    | awk -v want="    ${DEVICE_NAME} (" '
        /^-- / { ios = ($0 ~ /^-- iOS /) }
        ios && index($0, want) == 1 { line = $0 }
        END { if (line != "") print line }' \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

UDID=""
for attempt in 1 2 3; do
  UDID=$(find_udid)
  [ -n "$UDID" ] && break
  # Runtime lines end with the identifier: "iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5".
  RUNTIME=$(xcrun simctl list runtimes available | awk '/^iOS / { r = $NF } END { print r }')
  if [ -n "$RUNTIME" ]; then
    echo "Creating ${DEVICE_NAME} on ${RUNTIME}" >&2
    UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME") && break
  fi
  echo "No ${DEVICE_NAME} simulator yet (attempt ${attempt}); waiting for CoreSimulator" >&2
  sleep 10
done
[ -n "$UDID" ] || { echo "No simulator available for ${DEVICE_NAME}" >&2; exit 1; }

if [ "${1:-}" = "--boot" ]; then
  # Detach fully (stdin, stdout, stderr) so `$(...)` returns now instead of waiting for the boot.
  LOG="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/simulator-boot-${UDID}.log"
  nohup xcrun simctl bootstatus "$UDID" -b </dev/null >"$LOG" 2>&1 &
  echo "Booting ${DEVICE_NAME} ${UDID} in the background (log: ${LOG})" >&2
fi

echo "$UDID"
