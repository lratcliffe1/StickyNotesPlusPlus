# CLAUDE.md: StickyNotes++

A SwiftUI iOS app (iOS 17+) with a home-screen widget. It tracks a **morning-routine streak** and a **daily-task streak**, built on Atomic Habits' "never miss twice". It is Liam's personal app: it runs on his iPhone, installed through SideStore with a free Apple ID, and **his phone is in greyscale**.

## Layout

| Folder | What's in it |
|---|---|
| `StickyNote++/` | The app: `Features/Home` (screen, view model split into `+Storage`, `+Mutations`, `+DerivedState`), `Features/Calendar` (SwiftUI months; `CalendarModel` fetches one month at a time), `Features/Settings` (including Vault link), `Core/` (theme, components such as `SegmentedDayRing`, the day circle the calendar and the 7-day ring share, `UITestHarness`, `Vault/`: when the vault link runs: launch, foreground, background refresh, going to the background) |
| `StickyNote++ Widget Extension/` | The widget and its App Intents (complete and bump the top task) |
| `Shared/` | Compiled into the app, the widget **and** the tests: models, `Lists/` (`ListService`, the one write path for app and widget; the pure repeat, bump and streak rules), `Calendar/` (`CalendarRules`: month range, grid, a day's segments, planned days, fetch lookback; `DayMark`: a day state's greyscale shape), `HomeModel` (dates), persistence and the one-time V1 → V2 backfill, and `Vault/` (the vault link, `docs/VAULT-API.md`: fetching and reconciling `tasks.json`, writing `habits/YYYY-MM.json`, the Keychain token store, behind a `VaultHTTPClient` protocol so tests and the harness use a fake) |
| `StickyNote++Tests/` | XCTest unit tests. No host app, so they test `Shared/` code only |
| `scripts/` | `screenshots.sh` (simulator screenshots), `greyscale.swift`, and `ci-simulator.sh` (picks or creates the simulator both CI workflows run on) |

The Xcode project uses **folder-synchronised groups**: a new `.swift` file dropped into one of these folders is compiled automatically, so there's no need to edit `project.pbxproj`.

## Where things are decided

- `docs/ROADMAP.md`: the agreed order of work and each step's status.
- `docs/DECISIONS.md`: product rules Liam has decided (streaks, bumping, skipping). Code and tests follow these.
- `docs/VAULT-API.md`: the contract with Liam's vault (`tasks.json` in, `habits/YYYY-MM.json` out).
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
- **Greyscale first.** Every state must read without colour: carry meaning in shape, icon, text, weight, contrast or pattern, never hue alone. Check the `-grey.png` screenshots. A day or list state is always drawn with `SegmentedDayRing`, whose shapes come from `DayMark` (`Shared/Calendar/DayMark.swift`: filled ✓ done, partly filled by the share done (a sliver at least, a miss at most 85%), empty × missed, dashed nothing due, ↻ badge bumped; today's lists undecided until their streak deadline); never add a second drawing of it.
- **Never edit a shipped schema.** The store is versioned (`Shared/Persistence/SchemaVersions.swift`); `SchemaVersionTests.testVersionOneShapeIsPinned` and `testVersionTwoShapeIsPinned` fail if a model changes. V2 (step 2a) only *added* `Item` and `Occurrence`, so V1 and V2 share the four V1 classes. To change any model, add the next version and a stage; to change one of the shared V1 classes, first snapshot it as a nested type inside `StickyNotesSchemaV1`. Don't just update the tests. Writes go through `ListService`; nothing writes the V1 tables after the backfill. A store that can't migrate hits the `fatalError` in `StickyNotePlusPlusApp` at launch, on Liam's real data. The widget's `try?` (`WidgetTaskStore`) fails silently instead, and shows an empty widget.
- **No downgrades.** Once a V2 build has opened the store, a pre-V2 build can't open it (it would hit the launch `fatalError`). Never ship a build older than the store's schema. The app retries opening the store once after 0.5 s, in case the widget is migrating it at that moment.
- **App Group via `ALTAppGroups`.** With a free account, SideStore renames the App Group and lists the real identifier in Info.plist under `ALTAppGroups`. `SharedPersistence.appGroupIdentifier` resolves it at runtime. Never hardcode the group again; it crashed the app on launch.
- **The GitHub token lives only in the Keychain** (`KeychainVaultTokenStore`): never in UserDefaults, a file, a log or a screenshot, and the harness never touches it (an in-memory store and a fake GitHub). Nothing calls the real GitHub API in tests or CI.
- **Migration flags are written after the save**, never before (`HomeDataStore.migrateLegacyDayKeysIfNeeded`).
- **Dates go through `HomeModel`.** Day identity is the `dayKey` string (`YYYY-MM-DD`). Prefer the view model's `now` (overridable) to `Date()`. Not everything does yet (`selectedDay`, the relative-day label, `isViewingToday`), which is why the harness fixes only the time of day, with dates relative to the real today. `CalendarView` and the 7-day ring take Home's `now`.

## The screenshot harness

In Debug builds only, launching with `-uiScenario <morning|lateMorning|noon|daily|evening|empty|missedYesterday|missedTwice|states|statesMorning|fills|forgotEvening>` (and optionally `-uiScreen <home|calendar|settings|editLists|itemEditor|repeatPicker|bump|addOptions|deadline|vaultLink|pastComplete>`, `-uiList <morning|day|evening>`, `-uiMorningEnds <setTime|doneOrSkipped>`, `-uiEvening <on|off>`, `-uiTodayKeeps HH:MM` (today already stored at that set time), `-uiAppearance <light|dark>`, which the app forces because simctl's own switch can land after launch, `-uiDay <±N>` (Home on a day N days from today), `-uiCalendarMonth <±N>` (the calendar opened N months from the current one), `-uiOnlyLists <morning,day,…>` (the seed data keeps only those lists) and `-uiVault <off|updated|rejected|session>` (the vault link with a fake GitHub and an in-memory token; `session` adds a Claude session's file: one task under `done`, ticked, and one moved from today to the day after tomorrow, "Moved to …")) runs the app on an in-memory store with fixed sample data at a fixed time of day: `morning` and `missedYesterday` are 08:15, `lateMorning` 10:30 and `noon` 12:30, all with 2 of 6 routine items done; `daily`, `empty` and `missedTwice` are 14:00; `evening` is 21:30 with the routine done. In `daily` and `evening`, "Vitamins" was added to the morning list at 10:00, after the cutoff, and ticked: a bonus row. The settings default to "At a set time", 09:00, with the evening at 21:00; today's rules are stored from them on the first refresh, and a fixed clock never fires Home's boundary timer. The two `missed…` scenarios leave yesterday unfinished, to show the never-miss-twice banner. `forgotEvening` (08:15) leaves yesterday's evening two-thirds unticked, and `-uiScreen pastComplete` opens the retype sheet for the first open row of `-uiList` (default evening) on the `-uiDay` day: a forgotten tick on a past day. `states` (14:00) has only day-list one-offs, one state a day over the last week (done, partly done, missed, nothing due, bumped, today not yet), for the greyscale shapes; `statesMorning` (10:30) the same for the morning list alone, past its 09:00 set time, today finished late; `fills` (14:00) day-list one-offs again, one share done a day (1 of 6, 4 of 6, 1 of 20, done, 9 of 10, nothing, today 4 of 6 with a ticked "Must do" and "Due …"), for the arc fills. In this mode the app never opens the shared on-disk store, and settings and migration flags go to their own suite. See `StickyNote++/Core/UITestHarness/UITestHarness.swift`. To add a state: add a scenario or screen there, then add a row to `SHOTS` in `scripts/screenshots.sh` (its last column takes extra launch arguments, such as the settings). Long-press menus and `Menu`s can't be opened from launch arguments: show what they lead to instead. **Known quirk:** `simctl status_bar --time` accepts "08:15" but rejects the afternoon times we've tried, so the 14:00 shots keep a stale status-bar clock (the run log warns which); "10:30", "12:30" and "9:30" (for 21:30) do set. The app's own time in them is right.

## Shipping a build to the phone

1. Run the **Build IPA for SideStore** workflow (Actions → Run workflow, or `gh workflow run "Build IPA for SideStore"`) and download the `StickyNotesPlusPlus-ipa` artifact.
2. Copy the `.ipa` into iCloud Drive as `StickyNotes.ipa`, overwriting the previous build: one file. The build's branch and sha go in the commit or PR, not the filename.
3. Liam installs it: SideStore → My Apps → + → the file → "Register App ID for each extension". LocalDevVPN must be connected.

## Known weak spots (review, 2026-10-11)

Fix these as the planned work reaches them, not in passing:
- Each day's flip-time rules (step 3) live in the App Group defaults as one JSON dictionary keyed by `dayKey` (`DayRulesStore`), not in the store. The app and the widget both read-modify-write it; a settings change made at the very moment the widget first reads a new day could lose one write. Days before step 3 have no record and use 09:00. Records decode one by one with field defaults; if any record can't be read, nothing is written over it, and the app and widget both judge today by the settings as they are (`DayRulesStore.resolvedHistory`).
- Only today's occurrences are created, when the app or widget first reads the day. A day nobody opens has no rows, so streaks judge it by what was due (`ListRules.unopenedMisses`): an item due that day is a miss on its period end. Any row at all for a list marks the day as opened for that list, including a one-off added ahead of time or bumped in.
- Streaks read each list's whole history on every refresh. Fine at today's size; not measured at years of data. The ring and the calendar fetch only their own days (`ListService.dayLooks(from:through:)`: the range plus the longest repeat period before it, so a yearly item makes every range read a year back), and every item on each read.
- The app and the widget both write the store without coordinating. Item occurrences have ids derived from (item, scheduled day), so both creating today's rows lands on one row, and the backfill only inserts rows that are absent.
- `CalendarView` (SwiftUI, step 4) caches each month and re-reads on returning to the foreground or a new day, not on a widget write while the app stays in front. It opens on the current month with `ScrollViewReader.scrollTo` on a `LazyVStack`, so with many months of history above it the first position rests on estimated heights (it scrolls twice to settle). Dynamic Type is checked at the default size only; the day circle is capped at 48 pt.
- Xcode 26 will respect the targets' `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, which Xcode 16 ignores. Expect to mark the schema enums (and similar) `nonisolated` when CI moves up.
