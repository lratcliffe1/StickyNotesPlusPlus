Implementation Plan — Sticky Notes, Sticky Life

This implementation plan synthesizes PROJECT_SPEC.md (product intent and UX philosophy) with Spec.md (authoritative implementation details). It preserves the calm, gently opinionated UX while adhering strictly to the technical and behavioral rules in Spec.md.



1) Scope & Constraints
- Platform: iPhone only, portrait only
- OS: iOS 17+
- Tech: SwiftUI, SwiftData + CloudKit
- Offline-first, single user per Apple ID
- Last-write-wins conflict resolution (no `modifiedAt` in v1)
- UK English copy
- Privacy: no analytics, no tracking, iCloud sync only



2) Product Principles (from PROJECT_SPEC.md)
- Gently opinionated: nudge behavior, never scold or block progress
- Context over choice: show one primary list (Morning or Daily) on Home
- Friction with intent: reduce procrastination; provide button alternatives to gestures
- Calm visual language: minimal copy, soft transitions, subtle color shifts
- Read-only history; no retroactive editing
- Non-goals: no tags/folders/projects, no task priorities, no collaboration, no analytics beyond iCloud sync



3) Architecture Overview
- Layers
  - Models (SwiftData): MorningRoutineTemplateItem, MorningRoutineEntry, DailyTask, optional DayRecord cache
  - Repositories
    - RoutineRepository: template CRUD, daily generation of MorningRoutineEntry
    - TasksRepository: DailyTask CRUD, bumping
    - HistoryRepository: date-range queries, completion summaries, streak calculation helpers
    - NotificationScheduler (scaffold until M4): schedule/cancel per Spec.md
    - WidgetsBridge (scaffold until M4): shared logic and intents hooks
  - View Models (MainActor)
    - HomeViewModel: contextual list selection (Morning vs Daily), completion toggles, 7-day data, streak exposure
    - CalendarViewModel: read-only grid data, selected day management
    - AddViewModel: creation of DailyTask (title, date, isBumpable)
    - SettingsViewModel: morning template CRUD, morning mode configuration, notification toggles
  - Utilities
    - DateUtil: normalize to local day key, compute ranges (week/month), morning mode windows
    - SelectedDayContext: `@SceneStorage` day key, defaults to today



4) Data Models (Spec.md authoritative)
- MorningRoutineTemplateItem
  - id: UUID
  - title: String
  - sortOrder: Int
  - targetTime: DateComponents?
- MorningRoutineEntry
  - id: UUID
  - date: Date (normalized start-of-day, local timezone)
  - titleSnapshot: String
  - targetTimeSnapshot: DateComponents?
  - isCompleted: Bool
  - completedAt: Date?
- DailyTask
  - id: UUID
  - date: Date (normalized)
  - title: String
  - isCompleted: Bool
  - completedAt: Date?
  - bumpCount: Int
  - isBumpable: Bool
- Optional DayRecord cache
  - date: Date
  - morningCompletion: Double
  - dailyCompletion: Double

Data & Storage decisions
- Identifiers: UUID for all entities; no `@Attribute(.unique)` in v1
- Normalized Day: `Calendar.current.startOfDay(for:)` in local timezone
- Indexes: add index on `date` for MorningRoutineEntry, DailyTask (and DayRecord if used)
- CloudKit: default private iCloud DB with SwiftData; last-write-wins



5) Time & Day Rules
- Local timezone always; new day at 00:00 local
- Morning mode configuration (@AppStorage)
  - Modes: `cutoff` (default) and `wakeWindow`
  - Defaults: `morningCutoffTime = 09:00`, `wakeUpTime = 07:00`, `morningWindowDurationMinutes = 90`
- Morning list is shown until all morning items are completed OR cutoff/window expires
- Late completion updates history but does NOT count toward streak



6) Completion, Streaks, Never Miss Twice
- Completion %
  - morning: completed/total; daily: completed/total
  - if total == 0 → treat as 1.0 with higher transparency
- Streak
  - Increment only when morning completion reaches 1.0 before cutoff/window
  - Breaks on any miss
  - Zero-item days do NOT advance or preserve streak
- Never Miss Twice
  - If yesterday < 1.0, today must reach 1.0 to avoid “twice”



7) Navigation & Selected Day
- TabView with four tabs: Home, Calendar, Add, Settings
- Each tab can host its own NavigationStack
- Selected Day Context
  - Stored in `@SceneStorage` as normalized day key; default to today
  - Calendar → Home loop: tapping a day sets selected day and returns to Home
  - “Today” button resets context; Calendar preserves scroll position



8) Home UI
- Header
  - Left: morning streak count
  - Center: last 7 days as DiagonalSplitCircle row; labels under circles; today highlighted
  - Tap header → switches to Calendar tab
- Contextual Sticky Note
  - Shows Morning or Daily list based on Time & Day Rules
  - Read-only when viewing past days (history immutable)
  - Modern sticky-note card style (digital, not skeuomorphic)
- Visual Language
  - Solid diagonal split circles for progress
  - Red → green gradient for completion
  - Persistent ink-style strike-through for completed items



9) Calendar (Read-only History)
- Month grid; each cell shows DiagonalSplitCircle with completion mix
- Today clearly highlighted
- Tap day → set Selected Day Context → navigate Home
- “Today” button to jump back



10) Add Screen
- Create DailyTask for selected day
- Fields: title, date, “Must happen today” (sets `isBumpable = false`)



11) Settings
- Morning template CRUD + reorder (affects next-day generation)
- Morning mode configuration (cutoff/wakeWindow, times)
- Notification toggles + times (scheduling implemented in M4)



12) Interaction — Ink Strike
- Horizontal drag gesture only
- Completion toggles when drag covers >50% of the row’s rendered width
- Ink line remains visible (persistent strike)
- Undo
  - Explicit Undo button when completed
  - Tap-to-toggle also available
- All gesture actions have button alternatives



13) Task Bumping & Urgency
- Only allowed when `isBumpable == true`
- Bump creates a new task for tomorrow with copied `title` and `isBumpable`
- New task starts with `isCompleted = false`, `completedAt = nil`
- `bumpCount` increments on the NEW task instance
- Urgency colour ramps toward red as `bumpCount` increases; clamp visuals at `bumpCount >= 5`



14) Notifications (Spec.md behavior; scheduled for M4 delivery)
- Local notifications only; calm, practical tone
- Types
  - Morning reminder
  - Daily reminder
  - Never miss twice (morning)
  - Never miss twice (daily)
- Scheduling rules
  - Request authorization when user first enables any notification
  - Reschedule on app launch, settings changes, completion changes
  - Day rollover handled next launch (no background requirement in v1)
  - Identifiers: `morningReminder`, `dailyReminder`, `neverMissTwiceMorning`, `neverMissTwiceDaily`



15) Widgets (Spec.md behavior; scheduled for M4 delivery)
- Sizes: Small (7-day circles), Medium (contextual tasks), Large (combined)
- Rules
  - Same context logic as app
  - Interactive completion via AppIntent (tap again = undo)
  - Does not open app on completion
  - Refresh timelines after intent completes and at midnight



16) Accessibility
- Dynamic Type throughout
- VoiceOver labels for all interactive elements
- Button alternatives for gestures
- Sufficient contrast for all colour states



17) Haptics
- Subtle haptic on streak increment only
- No haptics for basic completion



18) Error Handling
- CloudKit issues surfaced as minimal, non-blocking banner
- Copy example: “Sync delayed — working offline.”
- App remains usable offline at all times



19) Privacy
- No analytics or tracking
- Data belongs to the user and stays within their iCloud account



20) Sync & Persistence
- SwiftData with CloudKit private database
- Last-write-wins merge policy
- No `modifiedAt` field in v1
- Index `date` fields for MorningRoutineEntry, DailyTask (and DayRecord if used)



21) Build Order (from Spec.md)
1. SwiftData models
2. Date utilities
3. DiagonalSplitCircle
4. Home header
5. Contextual sticky note
6. Ink strike gesture
7. Calendar
8. Add screen
9. Settings
10. Widgets (spec scaffolding earlier; functional delivery in M4)



22) Milestones & Deliverables

M1 — Foundations
- Data models and repositories
- Settings: Morning template CRUD + reorder; morning mode config persistence
- MorningRoutineEntry generation on first open of a day (idempotent)
- Home: contextual sticky (Morning vs Daily), basic completion with persistent strike
- Add screen: create DailyTask (title, date, isBumpable)
- Accessibility baseline; offline-first; CloudKit integration; minimal banner handling

M2 — Consistency
- Home header: 7-day DiagonalSplitCircle row + streak count; today highlighted; tap → Calendar
- Streak calculation and display (late completion does not increment)
- Calendar: read-only month grid, color-coded completion; Selected Day loop back to Home; Today button
- Gentle in-app prompts (non-blocking) for at-risk states (no notifications yet)

M3 — Delight
- Ink strike polish (smooth, persistent)
- Visual urgency based on `bumpCount` with clamped ramp
- Micro-animations and subtle color blending aligned with calm tone
- Haptics: streak increment only

M4 — Extension
- Notifications: implement scheduling/unscheduling per Spec.md
- Widgets: interactive completion via AppIntent, undo, midnight refresh
- Groundwork for a future Mac app (shared models/sync; not in v1 scope)



23) Initial Task Breakdown (Weeks 1–3)

Week 1
- Project setup; SwiftData + CloudKit container; index `date` fields
- Implement models; DateUtil normalization; SelectedDayContext via `@SceneStorage`
- Settings: Morning template CRUD + reorder; morning mode config (@AppStorage)
- MorningRoutineEntry generation from template (idempotent per day)

Week 2
- Home: contextual sticky note; completion toggles with Ink Strike (baseline)
- Add screen: create DailyTask, including “Must happen today” → `isBumpable = false`
- Accessibility pass; minimal error banner for sync issues; offline-first validation

Week 3
- Home header: streak + 7-day DiagonalSplitCircle row; today highlighted; tap → Calendar
- Calendar: month grid, color-coded completion; Selected Day → Home; Today button; preserve scroll
- Streak logic and zero-total day transparency; late completion handling
- Sync validation across devices; test last-write-wins



24) Definition of Done (Spec.md)
- Context switching correct across time modes (cutoff/wakeWindow)
- History immutable (read-only past days)
- Widgets mirror app logic and support undo (delivered in M4)
- Sync stable across devices; app usable offline



25) Risks & Mitigations
- Gesture complexity → Provide explicit buttons as fallbacks; clear affordances; Undo button
- Scope creep → Enforce Non-Goals; keep Settings minimal; no advanced configuration
- CloudKit edge cases → Silent/minimal banners; offline-first; avoid blocking flows
- Timezone/Day boundary → Normalize dates; no retroactive recomputation



26) Testing Strategy (v1)
- Keep pure logic testable (date normalization, streak calculation, completion summaries)
- Smoke/UI tests for Home interactions, Calendar selection, Selected Day loop
- Manual test plan for sync, day rollover, morning mode switching



27) Copy & Tone
- UK English; calm, practical, encouraging
- Example phrases: “Keep it simple today.” “Just one win.” “Don’t miss twice.”



28) Non-Goals (Reaffirmed)
- No tags, folders, or projects
- No task priorities
- No collaboration or sharing
- No retroactive editing of history
- No analytics beyond iCloud sync



29) Glossary
- Morning Template — editable routine definition in Settings (via MorningRoutineTemplateItem)
- Morning Entry — per-day instance of a morning item (MorningRoutineEntry)
- Daily Task — task tied to a specific day (DailyTask)
- Bump Count — number of times a task was deferred (increments on new task)
- Selected Day Context — the day currently being viewed (`@SceneStorage`)

