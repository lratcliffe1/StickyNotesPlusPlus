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

UDID=$("$HERE/ci-simulator.sh")
echo "== building"

xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" COMPILER_INDEX_STORE_ENABLE=NO build -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/StickyNote++.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

# Compile the greyscale filter once rather than interpreting the script for every shot.
GREYSCALE="$DERIVED/greyscale"
swiftc -O "$HERE/greyscale.swift" -o "$GREYSCALE"

echo "== booting the simulator"
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "== installing and capturing"
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

# name | scenario | screen | appearance | list (optional: -uiList) | settings (optional: extra
# launch arguments, e.g. -uiMorningEnds doneOrSkipped -uiEvening off). The status-bar clock matches
# each scenario's time where simctl accepts it. Long-press menus and Menus can't be opened from
# launch arguments, so 16-add-options shows the add menu's result and 17-add-deadline the sheet its
# "Deadline…" opens. 05-settings is "At a set time" (the default) with the evening on. The app
# also forces the appearance (-uiAppearance), since simctl's switch can land after launch.
# 04-calendar opens on the current month, 24 on the next one (-uiCalendarMonth +1); 25 is Home three
# days ahead (-uiDay +3), with a planned one-off and the recurring items due that day. The calendar
# shots use a British locale (-AppleLocale en_GB), so weeks start on Monday as on Liam's phone.
# 27 and 28 keep only the morning list, then morning and day (-uiOnlyLists): one and two segments.
# 29–32 are the greyscale shapes (step 5), one list, one state a day: done, partly done, missed,
# nothing due, done with a bump (↻) twice, today nothing done yet; Home has the "↻2" row. 33–34 are
# the morning list alone at 10:30, past its 09:00 set time: done, done late, partly done, missed,
# all skipped, done, and today done late (85% filled with ×). 35–36 are arcs filled by the share
# done (fix round 1): 1 of 6, 4 of 6, 1 of 20 (the sliver), done, 9 of 10 (a miss, capped at 85%),
# nothing done, today 4 of 6 so far; Home has a ticked "Must do" and a ticked "Due …". 37 is the
# morning list at 14:00 with "Vitamins", added at 10:00 after the 09:00 cutoff and ticked: a bonus
# row, so the morning stays done (filled, ✓).
# 40–44 are the vault link (-uiVault: a fake GitHub and an in-memory token, never the network or
# the Keychain).
SHOTS=(
  "01-home-morning|morning|home|light|"
  "02-home-daily|daily|home|light|"
  "03-home-empty|empty|home|light|"
  "04-calendar|daily|calendar|light||-AppleLocale en_GB"
  "05-settings|daily|settings|light|"
  "06-home-morning-dark|morning|home|dark|"
  "07-banner-missed-yesterday|missedYesterday|home|light|"
  "08-banner-missed-twice|missedTwice|home|light|"
  "09-home-evening|daily|home|light|evening"
  "10-edit-lists-morning|daily|editLists|light|morning"
  "11-edit-lists-day|daily|editLists|light|day"
  "12-edit-lists-evening|daily|editLists|light|evening"
  "13-item-editor|daily|itemEditor|light|day"
  "14-repeat-picker|daily|repeatPicker|light|day"
  "15-bump-sheet-retype|daily|bump|light|"
  "16-add-options|daily|addOptions|light|"
  "17-add-deadline|daily|deadline|light|"
  "18-settings-set-time-dark|daily|settings|dark|"
  "19-settings-done-or-skipped-evening-off|daily|settings|light||-uiMorningEnds doneOrSkipped -uiEvening off"
  "20-home-evening-2130|evening|home|light|"
  "21-home-1030-done-or-skipped|lateMorning|home|light||-uiMorningEnds doneOrSkipped"
  "22-home-1230-done-or-skipped-still-morning|noon|home|light||-uiMorningEnds doneOrSkipped"
  "23-settings-applies-from-tomorrow|daily|settings|light||-uiMorningEnds doneOrSkipped -uiTodayKeeps 09:00"
  "24-calendar-next-month|daily|calendar|light||-uiCalendarMonth +1 -AppleLocale en_GB"
  "25-home-future-day|daily|home|light||-uiDay +3"
  "26-calendar-dark|daily|calendar|dark||-AppleLocale en_GB"
  "27-calendar-one-list|daily|calendar|light||-uiOnlyLists morning -AppleLocale en_GB"
  "28-calendar-two-lists|daily|calendar|light||-uiOnlyLists morning,day -AppleLocale en_GB"
  "29-states-home|states|home|light|"
  "30-states-calendar|states|calendar|light||-AppleLocale en_GB"
  "31-states-home-dark|states|home|dark|"
  "32-states-calendar-dark|states|calendar|dark||-AppleLocale en_GB"
  "33-states-morning-late|statesMorning|home|light|morning"
  "34-states-morning-calendar|statesMorning|calendar|light||-AppleLocale en_GB"
  "35-fills-home|fills|home|light|"
  "36-fills-calendar|fills|calendar|light||-AppleLocale en_GB"
  "37-home-morning-bonus|daily|home|light|morning"
  "40-home-vault-tasks|empty|home|light||-uiVault updated"
  "41-home-daily-vault-tasks|daily|home|light||-uiVault updated"
  "42-vault-link-not-set-up|daily|vaultLink|light|"
  "43-vault-link-updated|daily|vaultLink|light||-uiVault updated"
  "44-vault-link-token-not-accepted|daily|vaultLink|light||-uiVault rejected"
  "45-home-vault-session|daily|home|light||-uiVault session"
  "46-home-vault-session-dark|daily|home|dark||-uiVault session"
)

for shot in "${SHOTS[@]}"; do
  IFS='|' read -r name scenario screen appearance list settings <<<"$shot"
  list_args=()
  if [[ -n "$list" ]]; then list_args=(-uiList "$list"); fi
  settings_args=()
  if [[ -n "$settings" ]]; then read -r -a settings_args <<<"$settings"; fi
  # simctl refuses to replace an active override (it misreports this as "non-ISO date/time"),
  # so clear it first. A clock that still won't set only costs the status bar: warn and go on.
  clock="2:00"  # simctl only accepts 12-hour times here; "14:00" is rejected
  case "$scenario" in
    morning|missedYesterday) clock="08:15" ;;
    lateMorning|statesMorning) clock="10:30" ;;
    noon) clock="12:30" ;;
    evening) clock="9:30" ;;
  esac
  xcrun simctl status_bar "$UDID" clear || true
  if ! xcrun simctl status_bar "$UDID" override --time "$clock" \
      --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3; then
    echo "WARNING: status-bar clock not set for $name; its clock is wrong, not the app's time" >&2
  fi
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiScenario "$scenario" -uiScreen "$screen" -uiAppearance "$appearance" \
    ${list_args[@]+"${list_args[@]}"} ${settings_args[@]+"${settings_args[@]}"} >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  "$GREYSCALE" "$OUT/$name.png" "$OUT/$name-grey.png"
  echo "captured $name"
done
