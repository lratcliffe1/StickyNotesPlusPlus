# CLAUDE.md: StickyNotes++

A SwiftUI iOS app (iOS 17+) with a home-screen widget. It tracks a **morning-routine streak** and a **daily-task streak**, built on Atomic Habits' "never miss twice". It is Liam's personal app: it runs on his iPhone, installed through SideStore with a free Apple ID, and **his phone is in greyscale**.

## Layout

| Folder | What's in it |
|---|---|
| `StickyNote++/` | The app: `Features/Home` (screen, view model split into `+Storage`, `+Mutations`, `+DerivedState`), `Features/Calendar`, `Features/Settings`, `Core/` (theme, components, `UITestHarness`) |
| `StickyNote++ Widget Extension/` | The widget and its App Intents (complete and bump the top task) |
| `Shared/` | Compiled into the app, the widget **and** the tests: models, `Lists/` (`ListService`, the one write path for app and widget; the pure repeat, bump and streak rules), `HomeModel` (dates), persistence and the one-time V1 → V2 backfill |
| `StickyNote++Tests/` | XCTest unit tests. No host app, so they test `Shared/` code only |
| `scripts/` | `screenshots.sh` (simulator screenshots), `greyscale.swift`, and `ci-simulator.sh` (picks or creates the simulator both CI workflows run on) |

The Xcode project uses **folder-synchronised groups**: a new `.swift` file dropped into one of these folders is compiled automatically, so there's no need to edit `project.pbxproj`.

## Where things are decided

- `docs/ROADMAP.md`: the agreed order of work and each step's status.
- `docs/DECISIONS.md`: product rules Liam has decided (streaks, bumping, skipping). Code and tests follow these.
- Harness: `/verify` (CI, screenshots, blind review, PR notes), `/ship` (install build for the phone), and the `checker` agent (blind adversarial review).

## Working method

1. **Plan, then wait for a yes.** Anything beyond a one-line fix gets a written plan with its design decisions and acceptance checks. Liam signs it off before any code. A detailed request is input to the plan, never its approval.
2. **One feature, one branch, one PR.** Never push product changes straight to `main`.
3. **Verify like a user, and declare what you didn't.** Xcode is **not installed** on Liam's Mac, so verification happens in CI:
   - `iOS Quality` builds the app and widget and runs the unit tests.
   - `Screenshots` (every push, like `iOS Quality`) opens each harness state in the simulator and uploads colour and **greyscale** PNGs. Download them (`gh run download <id> -n screenshots`) and actually look at them before calling a UI change done.
   - Every PR body has a **Verified** and a **Not verified** list. Liam's phone is the final check.
4. **Review before merge.** Get a fresh-context review that sees the plan's acceptance checks and the diff, not the builder's summary.

## Rules that bind

- **Apple's Human Interface Guidelines govern every UI and UX decision:** native controls, standard gestures, system fonts and spacing, Dynamic Type and accessibility labels.
- **Greyscale first.** Every state must read without colour: carry meaning in shape, icon, text, weight, contrast or pattern, never hue alone. Check the `-grey.png` screenshots.
- **Never edit a shipped schema.** The store is versioned (`Shared/Persistence/SchemaVersions.swift`); `SchemaVersionTests.testVersionOneShapeIsPinned` and `testVersionTwoShapeIsPinned` fail if a model changes. V2 (step 2a) only *added* `Item` and `Occurrence`, so V1 and V2 share the four V1 classes. To change any model, add the next version and a stage; to change one of the shared V1 classes, first snapshot it as a nested type inside `StickyNotesSchemaV1`. Don't just update the tests. Writes go through `ListService`; nothing writes the V1 tables after the backfill. A store that can't migrate hits the `fatalError` in `StickyNotePlusPlusApp` at launch, on Liam's real data. The widget's `try?` (`WidgetTaskStore`) fails silently instead, and shows an empty widget.
- **No downgrades.** Once a V2 build has opened the store, a pre-V2 build can't open it (it would hit the launch `fatalError`). Never ship a build older than the store's schema. The app retries opening the store once after 0.5 s, in case the widget is migrating it at that moment.
- **App Group via `ALTAppGroups`.** With a free account, SideStore renames the App Group and lists the real identifier in Info.plist under `ALTAppGroups`. `SharedPersistence.appGroupIdentifier` resolves it at runtime. Never hardcode the group again; it crashed the app on launch.
- **Migration flags are written after the save**, never before (`HomeDataStore.migrateLegacyDayKeysIfNeeded`).
- **Dates go through `HomeModel`.** Day identity is the `dayKey` string (`YYYY-MM-DD`). Prefer the view model's `now` (overridable) to `Date()`. Not everything does yet (`selectedDay`, the relative-day label, `isViewingToday`, `CalendarView`), which is why the harness fixes only the time of day, with dates relative to the real today.

## The screenshot harness

In Debug builds only, launching with `-uiScenario <morning|daily|empty|missedYesterday|missedTwice>` (and optionally `-uiScreen <home|calendar|settings|editLists|itemEditor|repeatPicker|bump|addOptions|deadline>` and `-uiList <morning|day|evening>`) runs the app on an in-memory store with fixed sample data at a fixed time of day: `morning` and `missedYesterday` are 08:15, with 2 of 6 routine items done; `daily`, `empty` and `missedTwice` are 14:00. The two `missed…` scenarios leave yesterday unfinished, to show the never-miss-twice banner. In this mode the app never opens the shared on-disk store, and settings and migration flags go to their own suite. See `StickyNote++/Core/UITestHarness/UITestHarness.swift`. To add a state: add a scenario or screen there, then add a row to `SHOTS` in `scripts/screenshots.sh`. Long-press menus and `Menu`s can't be opened from launch arguments: show what they lead to instead. **Known quirk:** `simctl status_bar --time` accepts "08:15" but rejects the afternoon times we've tried, so the 14:00 shots keep a stale status-bar clock (the run log warns which). The app's own time in them is right.

## Shipping a build to the phone

1. Run the **Build IPA for SideStore** workflow (Actions → Run workflow, or `gh workflow run "Build IPA for SideStore"`) and download the `StickyNotesPlusPlus-ipa` artifact.
2. Copy the `.ipa` into iCloud Drive as `StickyNotes-<branch>-<short-sha>.ipa`, so each build is told apart.
3. Liam installs it: SideStore → My Apps → + → the file → "Register App ID for each extension". LocalDevVPN must be connected.

## Known weak spots (review, 2026-10-11)

Fix these as the planned work reaches them, not in passing:
- The morning cutoff has no settings screen, so it's fixed at 09:00, and every past day is judged by today's cutoff. A per-day cutoff is step 3.
- Only today's occurrences are created, when the app or widget first reads the day. A day nobody opens has no rows, so streaks judge it by what was due (`ListRules.unopenedMisses`): an item due that day is a miss on its period end. Any row at all for a list marks the day as opened for that list, including a one-off added ahead of time or bumped in.
- Streaks, the ring and the calendar read each list's whole history on every refresh, and `CalendarView`'s `@Query` fetches every occurrence. Fine at today's size; not measured at years of data. Fetching only what's visible is step 4.
- The app and the widget both write the store without coordinating. Item occurrences have ids derived from (item, scheduled day), so both creating today's rows lands on one row, and the backfill only inserts rows that are absent.
- `CalendarView` uses a UIKit collection view with hand-computed heights. Its weeks start on Sunday, and it shows whole years (the current year ±1, widened to fit the data, plus a year's padding each side).
- Xcode 26 will respect the targets' `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, which Xcode 16 ignores. Expect to mark the schema enums (and similar) `nonisolated` when CI moves up.
