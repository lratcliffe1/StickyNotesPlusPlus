# Decisions

**What this is for:** product rules Liam has decided, dated, newest first. Code and tests follow these. When a rule changes, add a new entry that names the one it replaces; never edit an old entry. **What must NOT go in here:** plans and status (→ `ROADMAP.md`).

## 2026-10-11: lists, repeats and bumping (step 2 grilling)

- **Three lists: morning, day, evening.** Evening is a wind-down routine with its own streak and an optional start time when the app flips to it (flip times are step 3).
- **Recurring items on every list, plus one-offs.** Examples Liam named: check Now.md, exercise, a weekly gym session.
- **Repeats follow Apple Reminders:** Daily, Weekdays, Weekends, Weekly (chosen days), Every 2 Weeks, Monthly, Yearly, and Custom (every N days, weeks on chosen days, or months).
- **A recurring item exists from the day it's created onwards.** Deleting it removes it from that day onwards and keeps it on earlier days. Renaming applies from today; past days keep the title they had. Days link to items by ID, not title.
- **Order:** recurring items first, in their set order, then one-offs ("can't bump" ones at the top of the one-offs).
- **Bump limits, per item:** can't bump · up to N days · until a deadline date (e.g. Now.md items) · until the end of the week · unlimited. New one-offs default to **up to 3 days**.
- **Repeating items:** daily ones can't be bumped. Anything less frequent can be bumped day by day until the end of its period (week, 2 weeks, month…). Bumping moves only that occurrence. Not done by the period end counts as a miss on that last day.
- **Bumping should cost something:** it sits behind a swipe, never a single tap. A settings toggle (on by default) makes you retype the title, and you **may edit it**. Otherwise you confirm "Bump to tomorrow?". The bumped item stays **linked** to the original, so the chain is visible ("Bumped 2× · first added Mon as …"). Bumped days are marked as bumped in the ring and the calendar (readable in grey), and the header shows bumps this week. *(Liam: "sounds good for now, we can refine later after using".)*
- **Widget:** shows the top 3 open items of the current list, can complete any of them, and can bump one-offs. Skipping stays in the app.
- **Data:** a fresh start. The old Xcode-era history stays in the expired app and isn't recovered.

## 2026-10-11: streak rules (for step 2)

- **A bumped task counts as complete for the day it was bumped from.** The guard against abuse is friction plus limits (see "lists, repeats and bumping" above, which settles the retype question).
- **A day with nothing on a list is neutral** for that list's streak: it neither extends it nor breaks it. The UI shouldn't show it as 100%.
- **A skipped item drops out of that day's count.** Doing the rest still completes the day. Skipping everything makes the day neutral, not complete, but it still lets the list flip.
- **Recurring and one-off daily tasks both count** towards the daily streak.
- **Each day keeps the cutoff it had**, so changing the setting later doesn't recount past streaks.

## 2026-10-11: working rules

- **Greyscale first.** Liam's phone runs in greyscale, so every state has to read without colour.
- **Plan sign-off before building; one step per branch and PR;** every PR lists what was and wasn't verified.
