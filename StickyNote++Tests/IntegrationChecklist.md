# Stage 2 Test Matrix

## Unit-Style Scenarios (logic-focused)

- `HomeDataStore.dayFromStored` uses `dayKey` when valid and falls back to normalized `date` when missing/invalid.
- `HomeDataStore.nextSortOrder` appends at end by default and inserts before min when `insertAtTop` is enabled.
- `MorningModeProvider.load` clamps morning window duration into expected bounds and maps mode selection correctly.
- `DailyTaskMutationService.createTask` trims title, normalizes day, and sets `isBumpable` from `mustHappenToday`.

## Integration Scenarios (app behavior)

- Home: toggling morning entries updates progress/streak and persists expected completion timestamps.
- Home: toggling a completed bumped task restores original state and removes linked bumped task.
- Home: bumping a daily task marks source complete, creates tomorrow task with incremented bump count.
- Home: completing a past task requires exact typed confirmation and stamps completion at end-of-day.
- Settings: adding daily task follows the same write path/sort semantics as home composer.
- Settings: editing routine items no longer saves every keystroke; submit/disappear persists changes.

## Migration Scenarios

- Launch with legacy empty `dayKey` values: migration fills keys and does not re-run after completion flags are set.
- Legacy mixed `sortOrder` values: migration rewrites order per day in stable sequence.
- Day record upsert avoids writes when morning/daily completion values are unchanged.

## App / Widget Parity Scenarios

- Same morning mode inputs produce same contextual list decision in app and widget snapshot.
- Completing task from widget updates app-visible task state and day record.
- Bumping task from widget mirrors app bump semantics (tomorrow task, completion metadata, bump linkage).
- Widget snapshot and app home list show the same top uncompleted items ordering for the current day.

## Smoke Flow Sequence

1. Seed 2-3 morning templates and 4+ daily tasks for today.
2. Complete one morning and one daily task in app.
3. Bump one eligible daily task in app.
4. Trigger widget complete and widget bump actions.
5. Reopen app, verify parity for task states, day progress, and streak fields.
