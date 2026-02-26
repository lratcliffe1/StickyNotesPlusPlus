# Sticky Notes, Sticky Life

I wanted an advanced sticky note app where I can track both my recurring morning routine streak and my daily task streak.
I based it on ideas from James Clear's _Atomic Habits_:

- never miss twice
- make it easy
- make it visible
- make it rewarding

I now use this app daily.

## What I have done

- Built an iOS app in SwiftUI (iOS 17+) with a Widget extension.
- Added two streak systems:
  - Morning routine streak
  - Daily tasks streak
- Implemented "never miss twice" behavior with freeze/risk feedback.
- Built a contextual sticky note that switches between Morning Routine and Daily Tasks based on time + completion state.
- Added daily task bumping ("move to tomorrow") with urgency coloring.
- Added a read-only calendar history view with 7-day and per-day progress visuals.
- Added a widget that shows the top 3 uncompleted items and supports completion from the widget.

## Explain the code

- `StickyNote++/StickyNotePlusPlusApp.swift`
  - App entry point. Creates the shared SwiftData container and injects it into the environment.
- `StickyNote++/Core/Persistence/SharedPersistence.swift`
  - Defines the shared schema (`MorningRoutineTemplateItem`, `MorningRoutineEntry`, `DailyTask`, `DayRecord`).
  - Uses an App Group store so app + widget read/write the same data.
- `StickyNote++/Features/Home/`
  - Main product logic/UI.
  - `HomeViewModel.swift` drives state, list switching, progress, streaks, and "never miss twice" flags.
  - `HomeViewModel+Storage.swift` contains fetch/reconcile/save logic for SwiftData.
  - `HomeModel.swift` contains pure logic for date normalization, completion math, streak math, and morning-window rules.
  - `View/` contains the sticky note card, streak header, ink-strike interactions, and day navigation.
- `StickyNote++/Features/Calendar/View/CalendarView.swift`
  - Read-only calendar with per-day morning/daily split progress.
- `StickyNote++/Features/Settings/View/`
  - Edit morning routine template items.
  - Add daily tasks (including "must happen today" / non-bumpable behavior).
- `StickyNote++ Widget Extension/`
  - Widget timeline + AppIntent completion.
  - `WidgetTaskStore.swift` mirrors core selection logic and updates shared data.

## Architecture choices

- **SwiftUI + MVVM**: UI is declarative, and business logic lives in `HomeViewModel` / `HomeModel`.
- **Shared local persistence first**: SwiftData in an App Group container keeps app and widget in sync without extra backend work.
- **Explicit day normalization**: all date comparisons use start-of-day to avoid edge-case bugs.
- **Separation of logic from storage**:
  - Pure rules in `HomeModel`
  - Persistence/fetch logic in `HomeViewModel+Storage`
  - UI composition in `View` files
- **Feature-oriented folders**: Home, Calendar, Settings, and Widget are split by behavior rather than by UIKit-style layers.

## What I have learnt

- Turning habit philosophy into code requires clear, testable rules (especially around streak cutoffs and day boundaries).
- Small UX details (visual progress, quick toggles, gentle warnings) matter more than adding lots of features.
- Shared app/widget data is easiest when storage is designed for both targets from day one.
- "Simple" habit products still need careful logic for edge cases (late completions, empty days, bump chains, deep links).

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
