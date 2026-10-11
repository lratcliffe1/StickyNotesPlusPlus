# CLAUDE.md: StickyNotes++

A SwiftUI iOS app (iOS 17+) with a home-screen widget. It tracks a **morning-routine streak** and a **daily-task streak**, built on Atomic Habits' "never miss twice". It is Liam's personal app: it runs on his iPhone, installed through SideStore with a free Apple ID, and **his phone is in greyscale**.

## Layout

| Folder | What's in it |
|---|---|
| `StickyNote++/` | The app: `Features/Home` (screen, view model split into `+Storage`, `+Mutations`, `+DerivedState`), `Features/Calendar`, `Features/Settings`, `Core/` (theme, components, `UITestHarness`) |
| `StickyNote++ Widget Extension/` | The widget and its App Intents (complete and bump the top task) |
| `Shared/` | Compiled into the app, the widget **and** the tests: models, `HomeModel` (pure date and streak rules), `HomeDataStore`, persistence |
| `StickyNote++Tests/` | XCTest unit tests. No host app, so they test `Shared/` code only |
| `scripts/` | `screenshots.sh` (simulator screenshots) and `greyscale.swift` |

The Xcode project uses **folder-synchronised groups**: a new `.swift` file dropped into one of these folders is compiled automatically, so there's no need to edit `project.pbxproj`.

## Working method

1. **Plan, then wait for a yes.** Anything beyond a one-line fix gets a written plan with its design decisions and acceptance checks. Liam signs it off before any code. A detailed request is input to the plan, never its approval.
2. **One feature, one branch, one PR.** Never push product changes straight to `main`.
3. **Verify like a user, and declare what you didn't.** Xcode is **not installed** on Liam's Mac, so verification happens in CI:
   - `iOS Quality` builds the app and widget and runs the unit tests.
   - `Screenshots` opens each harness state in the simulator and uploads colour and **greyscale** PNGs. Download them (`gh run download <id> -n screenshots`) and actually look at them before calling a UI change done.
   - Every PR body has a **Verified** and a **Not verified** list. Liam's phone is the final check.
4. **Review before merge.** Get a fresh-context review that sees the plan's acceptance checks and the diff, not the builder's summary.

## Rules that bind

- **Greyscale first.** Every state must read without colour: carry meaning in shape, icon, text, weight, contrast or pattern, never hue alone. Check the `-grey.png` screenshots.
- **Never edit a shipped schema.** The store is versioned (`Shared/Persistence/SchemaVersions.swift`). To change a model, add `StickyNotesSchemaV2`, snapshot V1's models as nested types inside `StickyNotesSchemaV1`, and add a migration stage. A store that can't migrate hits the `fatalError` in `StickyNotePlusPlusApp` at launch, on Liam's real data.
- **App Group via `ALTAppGroups`.** With a free account, SideStore renames the App Group and lists the real identifier in Info.plist under `ALTAppGroups`. `SharedPersistence.appGroupIdentifier` resolves it at runtime. Never hardcode the group again; it crashed the app on launch.
- **Migration flags are written after the save**, never before (`HomeDataStore.migrateLegacyDayKeysIfNeeded`).
- **Dates go through `HomeModel`.** Day identity is the `dayKey` string (`YYYY-MM-DD`). Use the view model's `now` (overridable), not `Date()`, in anything a test or the harness needs to control.

## The screenshot harness

In Debug builds only, launching with `-uiScenario <morning|daily|empty>` (and optionally `-uiScreen <home|calendar|settings>`) runs the app on an in-memory store with fixed sample data at a fixed time: `morning` is 08:15, with 2 of 6 routine items done; `daily` and `empty` are 14:00. See `StickyNote++/Core/UITestHarness/UITestHarness.swift`. To add a state: add a scenario or screen there, then add a row to `SHOTS` in `scripts/screenshots.sh`.

## Shipping a build to the phone

1. Run the **Build IPA for SideStore** workflow (Actions → Run workflow, or `gh workflow run "Build IPA for SideStore"`) and download the `StickyNotesPlusPlus-ipa` artifact.
2. Copy the `.ipa` into iCloud Drive.
3. Liam installs it: SideStore → My Apps → + → the file → "Register App ID for each extension". LocalDevVPN must be connected.

## Known weak spots (review, 2026-10-11)

Fix these as the planned work reaches them, not in passing:
- Leaving the app open overnight leaves it on yesterday.
- The morning cutoff has no settings screen, so it's fixed at 09:00.
- Routine days are matched to the routine **by title**, so a rename wipes today's tick.
- Bumping a task marks it complete, which keeps the streak alive.
- The app and the widget both write the store without coordinating.
- `CalendarView` uses a UIKit collection view with hand-computed heights. Its weeks start on Sunday, and it shows a fixed 2024–2028 range.
