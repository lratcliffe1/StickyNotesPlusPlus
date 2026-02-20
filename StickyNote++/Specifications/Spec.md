# Spec.md — Sticky Notes, Sticky Life (Implementation)

This document is the authoritative implementation specification for Xcode’s AI assistant.
All behavior should follow this spec literally unless explicitly marked as future-flexible.

---

## 1. Platform & Constraints

- iPhone only
- Portrait only
- iOS 17+
- SwiftUI
- SwiftData + CloudKit sync
- Offline-first
- Single user per Apple ID
- Last-write-wins conflict resolution
- UK English copy

---

## 2. App Structure

TabView with four tabs:
- Home
- Calendar
- Add
- Settings

NavigationStack per tab as needed.

---

## 3. Time & Day Rules

- Local timezone always applies.
- New day starts at 00:00 local time.
- All dates are normalized to local day boundaries.

### Morning mode (user-selectable):
1. **Time-of-day cutoff**
   - `morningCutoffTime` (default 09:00)
2. **Since wake-up**
   - `wakeUpTime` (time-of-day)
   - `morningWindowDuration` (minutes)

Morning list is shown until:
- all morning items are completed OR
- cutoff/window expires

Late completion does NOT count toward streak.

---

## 4. Data Models (SwiftData)

### MorningRoutineTemplateItem
- id: UUID
- title: String
- sortOrder: Int
- targetTime: DateComponents?

### MorningRoutineEntry
- id: UUID
- date: Date (normalized)
- titleSnapshot: String
- targetTimeSnapshot: DateComponents?
- isCompleted: Bool
- completedAt: Date?

### DailyTask
- id: UUID
- date: Date (normalized)
- title: String
- isCompleted: Bool
- completedAt: Date?
- bumpCount: Int
- isBumpable: Bool

### (Optional) DayRecord cache
- date: Date
- morningCompletion: Double
- dailyCompletion: Double

---

## 5. Completion & Streak Logic

### Completion %
- morning: completed / total
- daily: completed / total
- if total == 0 → treat as 1.0 with higher transparency

### Streak
- Increment only when morning completion reaches 1.0 before cutoff/window.
- Breaks on any miss.

### Never Miss Twice
- If yesterday < 1.0, today must reach 1.0 to avoid “twice”.

---

## 6. Home UI

### Header
- Left: morning streak count
- Center: last 7 days using DiagonalSplitCircle
- Labels under circles; today highlighted
- Tap → Calendar tab

### Contextual Sticky Note
- Shows Morning or Daily list based on rules
- Read-only when viewing past days
- Modern sticky-note card style

---

## 7. Calendar

- Read-only grid of all historical days
- Each cell shows DiagonalSplitCircle
- Tap day → set Selected Day Context → navigate Home
- “Today” button resets context

---

## 8. Interaction — Ink Strike

- Horizontal drag gesture only
- Completion toggles when drag covers >50% of text width
- Ink line remains visible
- If <50% → no effect

Undo:
- Explicit Undo button OR tap-to-toggle
- All gesture actions must have button alternatives

---

## 9. Task Bumping

- Only allowed when isBumpable == true
- Bump creates tomorrow task automatically
- bumpCount increments
- Urgency colour shifts smoothly toward red as bumpCount increases

---

## 10. Add Screen

- Add DailyTask to any selected day
- Fields:
  - title
  - date
  - “Must happen today” → isBumpable = false

---

## 11. Settings

- Morning template CRUD + reorder
- Morning mode configuration
- Notification toggles + times
- No advanced configuration

---

## 12. Notifications

- Local notifications only
- Sent only when relevant list incomplete
- Types:
  - Morning reminder
  - Daily reminder
  - Never miss twice (morning)
  - Never miss twice (daily)

Tone: calm, practical, encouraging

---

## 13. Widgets (WidgetKit + AppIntents)

Sizes:
- Small: 7-day circles
- Medium: contextual tasks
- Large: combined view

Rules:
- Same context logic as app
- Interactive completion via AppIntent
- Does not open app on completion
- Supports undo

---

## 14. Accessibility

- Dynamic Type
- VoiceOver labels
- Button alternatives for gestures
- Adequate contrast for all colour states

---

## 15. Haptics

- Subtle haptic on streak increment only
- No haptics for basic completion

---

## 16. Error Handling

- CloudKit issues surfaced as minimal, non-blocking banner
- App remains usable offline at all times

---

## 17. AI Build Order

1. SwiftData models
2. Date utilities
3. DiagonalSplitCircle
4. Home header
5. Contextual sticky note
6. Ink strike gesture
7. Calendar
8. Add screen
9. Settings
10. Widgets

---

Definition of Done:
- Context switching correct across time modes
- History immutable
- Widgets mirror app logic
- Sync stable across devices
---

## Appendix — App Decisions (v1)

### Data Model & Storage
- Identifiers: Use UUID for all entities. No extra stable keys. Do not use `@Attribute(.unique)` in v1.
- Indexing: Add an index on `date` for `MorningRoutineEntry` and `DailyTask` (and `DayRecord` if used). No index for `isCompleted` in v1.
- Normalized Day: Store `Calendar.current.startOfDay(for:)` in local timezone at creation; persist the resulting `Date` as the day key.
- CloudKit Sync: Use SwiftData default private iCloud database, no custom zones, all fields sync.
- Conflict Resolution: Rely on SwiftData/CloudKit default last-write-wins. No `modifiedAt` in v1.

### Morning Mode Configuration
- Persistence: Use `@AppStorage` for preferences (not SwiftData).
- Mode: `morningMode` enum with two mutually exclusive modes: `cutoff` (default) and `wakeWindow`.
- Defaults: `morningCutoffTime = 09:00`, `wakeUpTime = 07:00`, `morningWindowDurationMinutes = 90`.

### Streak Logic
- Zero-item days do NOT advance or preserve streak (still display 1.0 completion with higher transparency).
- Late completion updates history but does not increment streak.
- No retroactive recomputation due to timezone/system time changes; streak is computed over stored day keys.

### Daily Tasks & Bumping
- Bump creates a new task for tomorrow with copied `title` and `isBumpable`; resets `isCompleted = false`, `completedAt = nil`.
- `bumpCount` increments on the NEW task instance (urgency reflects current state).
- Non-bumpable tasks: bump action disabled/hidden with explanation (no silent ignore).
- Urgency clamp: visual urgency clamps at `bumpCount >= 5` (count may continue increasing numerically).

### Calendar & Selected Day Context
- Store `selectedDay` (day key `Date`) in `@SceneStorage`; default to today.
- Calendar preserves scroll position when switching tabs; "Today" button jumps to current day.

### Interaction — Ink Strike & Undo
- 50% threshold is based on the row’s rendered content width (text + padding) via `GeometryReader`.
- Provide both: tap-to-toggle (primary) and a small Undo icon button when completed (explicit accessibility target).

### Notifications
- Request authorization when user first enables any notification.
- Reschedule notifications on: app launch, settings changes, completion changes. Day rollover handled next launch (no background requirement in v1).
- No quiet hours in v1.
- Identifiers: `morningReminder`, `dailyReminder`, `neverMissTwiceMorning`, `neverMissTwiceDaily`.

### Widgets & AppIntents
- Provide a toggle-completion AppIntent (tap again = undo).
- Refresh widget timelines after intent completes and at midnight.

### Accessibility & Copy
- UK English; calm, practical tone. Example phrases: “Keep it simple today.” “Just one win.” “Don’t miss twice.”
- Support all Dynamic Type sizes. At accessibility sizes, allow rows to grow and wrap titles up to 2 lines; ensure button alternatives remain visible.

### Error Handling & Banners
- Single banner at a time; auto-dismiss after ~5 seconds; VoiceOver announcement.
- Sync copy: “Sync delayed — working offline.”

### Testing & DoD
- No mandatory tests in v1; keep pure logic (date normalization, streak calc) testable for later.
- PR template/checklist optional for v1.

