# StickyNotes++

I wanted an advanced sticky note app where I can track both my recurring morning routine streak and my daily task streak.
I based it on ideas from James Clear's _Atomic Habits_:

- never miss twice
- make it easy
- make it visible
- make it rewarding

I now use this app daily.

## What I have done

- iOS app in SwiftUI (iOS 17+) with a Widget extension.
- Two streak systems:
  - Morning routine streak
  - Daily tasks streak
- "Never miss twice" behavior with freeze/risk feedback.
- Contextual sticky note that switches between Morning Routine and Daily Tasks based on time + completion state.
- Daily task bumping ("move to tomorrow") with urgency coloring.
- Read-only calendar history view with 7-day and per-day progress visuals.
- Widget that shows the top 3 uncompleted items and supports completion actions.
- Stable `dayKey` (`YYYY-MM-DD`) identity for day-based queries.
- One-time migration logic for rows missing `dayKey`.
- Shared models/settings/persistence/domain logic under `Shared/`, compiled by both app and widget targets.
- Shared repository-backed data layer for app + widget parity.
- Structured logging and baseline CI checks (build + lint + format).

## Explain the code

- `StickyNote++/StickyNotePlusPlusApp.swift`
  - App entry point. Creates the shared SwiftData container and injects it into the environment.
- `Shared/Persistence/SharedPersistence.swift`
  - Defines the shared schema (`MorningRoutineTemplateItem`, `MorningRoutineEntry`, `DailyTask`, `DayRecord`).
  - Uses an App Group store so app + widget read/write the same data.
  - Includes legacy-store migration into the App Group location.
- `Shared/Home/HomeModel.swift`
  - Pure rules for date normalization, stable day keys, completion math, streak math, and morning-window rules.
- `Shared/Home/HomeDataStore.swift`
  - Shared SwiftData workflows: fetch, migration, reconcile, and day-record upsert logic.
- `Shared/Home/HomeRepository.swift`
  - Repository contract + SwiftData implementation used by both app and widget call-sites.
- `Shared/Home/MorningModeProvider.swift`
  - Shared morning-settings parsing/clamping to keep app and widget behavior aligned.
- `Shared/Home/DailyTaskMutationService.swift`
  - Shared task creation write path used by Home and Settings flows.
- `Shared/Models/`
  - Shared SwiftData models used by both targets.
- `Shared/Settings/AppSettings.swift`
  - Shared defaults keys and time conversion helpers for morning mode settings.
- `Shared/Support/AppLogger.swift`
  - Centralized structured logging categories for persistence/widget error reporting.
- `StickyNote++/Features/Home/`
  - Main product logic/UI.
  - `HomeViewModel.swift` is the orchestrator for observable state + dependency wiring.
  - `HomeViewModel+Storage.swift` wraps repository-backed fetch/save/migration calls.
  - `HomeViewModel+Mutations.swift` contains user-driven write actions (toggle/add/bump/reorder).
  - `HomeViewModel+DerivedState.swift` calculates progress/streak/never-miss-twice/contextual-list state.
  - `View/` contains the sticky note card, streak header, ink-strike interactions, and day navigation.
- `StickyNote++/Features/Calendar/View/CalendarView.swift`
  - Read-only calendar with per-day morning/daily split progress, keyed by stable day IDs.
- `StickyNote++/Features/Settings/View/`
  - Edit morning routine template items.
  - Add daily tasks (including "must happen today" / non-bumpable behavior).
- `StickyNote++ Widget Extension/`
  - Widget timeline + AppIntent completion.
  - `WidgetTaskStore.swift` uses the shared repository paths for migration, selection, and updates.

## Architecture choices

- **SwiftUI + MVVM**: UI is declarative, and feature state lives in `HomeViewModel`, while pure rules live in `Shared/Home/HomeModel`.
- **Shared source of truth across targets**: the `Shared/` folder is compiled into both app and widget targets to keep models/settings/rules aligned.
- **Shared local persistence first**: SwiftData in an App Group container keeps app and widget in sync without extra backend work.
- **Stable day identity across time zones**: day-based queries use `dayKey` (`YYYY-MM-DD`) plus normalized dates to avoid timezone-related fetch bugs.
- **Separation of concerns**:
  - Pure rules in `Shared/Home/HomeModel`
  - Persistence/repository logic in `Shared/Home/HomeDataStore` + `Shared/Home/HomeRepository`
  - Shared write/settings logic in `DailyTaskMutationService` + `MorningModeProvider`
  - Home orchestration in `HomeViewModel` extensions (`+Storage`, `+Mutations`, `+DerivedState`)
  - UI composition in feature `View` files
- **Feature-oriented folders**: Home, Calendar, Settings, and Widget are split by behavior rather than by UIKit-style layers.

## Run locally

### Requirements

- Xcode 17+
- iOS 17+ simulator or device

### Xcode

1. Open `StickyNote++.xcodeproj`.
2. Select the `StickyNote++` scheme.
3. Choose an iOS Simulator (for example, iPhone 16).
4. Press Run.

### CLI build (simulator)

```bash
xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

## Tests

### What exists

- Unit tests live in `StickyNote++Tests/`.
- Current stable-core coverage includes:
  - day-key and completion behavior (`HomeModelTests`)
  - morning settings parsing/clamping (`MorningModeProviderTests`)
  - shared task creation semantics (`DailyTaskMutationServiceTests`)
  - migration and idempotent upsert behavior (`HomeDataStoreTests`)

### Run tests in Xcode

1. Open `StickyNote++.xcodeproj`
2. Select scheme `StickyNote++`
3. Select an iOS **Simulator** destination (not physical device)
4. Press `Cmd+U`

### Run tests via CLI

```bash
xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -destination "platform=iOS Simulator,name=iPhone 15" test
```

### Quality checks

- SwiftLint config: `.swiftlint.yml`
- SwiftFormat config: `.swiftformat`
- CI workflow: `.github/workflows/ios-quality.yml` (build app/widget + format/lint checks)
