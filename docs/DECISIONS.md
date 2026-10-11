# Decisions

**What this is for:** product rules Liam has decided, dated, newest first. Code and tests follow these. When a rule changes, add a new entry that names the one it replaces; never edit an old entry. **What must NOT go in here:** plans and status (→ `ROADMAP.md`).

## 2026-10-11: streak rules (for step 2)

- **A bumped task counts as complete for the day it was bumped from.** The guard against abuse is friction: some tasks can only be bumped a limited number of times (the existing per-task `isBumpable`, possibly a maximum count). *Open:* whether bumping should make you retype the task as deliberate friction. It currently copies the title.
- **A day with nothing on a list is neutral** for that list's streak: it neither extends it nor breaks it. The UI shouldn't show it as 100%.
- **A skipped item drops out of that day's count.** Doing the rest still completes the day. Skipping everything makes the day neutral, not complete, but it still lets the list flip.
- **Recurring and one-off daily tasks both count** towards the daily streak.
- **Each day keeps the cutoff it had**, so changing the setting later doesn't recount past streaks.

## 2026-10-11: working rules

- **Greyscale first.** Liam's phone runs in greyscale, so every state has to read without colour.
- **Plan sign-off before building; one step per branch and PR;** every PR lists what was and wasn't verified.
