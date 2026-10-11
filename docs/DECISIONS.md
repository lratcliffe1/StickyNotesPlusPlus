# Decisions

**What this is for:** product rules Liam has decided, dated, newest first. Code and tests follow these. When a rule changes, add a new entry that names the one it replaces; never edit an old entry. **What must NOT go in here:** plans and status (→ `ROADMAP.md`).

## 2026-10-11 (overnight, step 2b): controls, provisional calls

Taken while building step 2b with Liam asleep (see the working rules in the evening entry below). Each is *provisional: Liam to confirm*.

**From the plan**
- **Editing an item's repeat applies from today.** The old item ends and a new one starts today, or tomorrow if today's occurrence is already done, skipped or bumped, so past days are never recounted. A copy already bumped onto a later day stays with the old item and finishes its period. A bump-limit edit changes the item and today's open occurrence only. A title-only edit is a rename from today, as before. *Provisional: Liam to confirm.*
- **Delete on a recurring row** deletes the item from today on (as in Edit lists), after a confirmation. *Provisional: Liam to confirm.*
- **Edit… on a one-off** edits its title, deadline and bump limit for that row only (not the rows earlier in its bump chain). On a recurring row it opens the item editor. *Provisional: Liam to confirm.*
- **"N bumps this week"** counts bump actions on days in the current locale week up to today, across all three lists, whichever day Home is showing. *Provisional: Liam to confirm.*

**Made while building**
- **Bumping is only in the long-press menu.** The one-tap bump button on day-list rows is gone, since bumping should never be a single tap. *Provisional: Liam to confirm.*
- **The add menu's bump limits** are Up to 1, 3 (the default) or 7 days, End of week, Until deadline, and Unlimited. Choosing Until deadline with no deadline opens the date picker. A deadline on its own leaves the limit as it is. The chosen options show in words under the add field, and reset after each add. *Provisional: Liam to confirm.*
- **An item's bump limit** (non-daily repeats only) is one of: Until its period ends (the default), Up to N days, Until the end of the week, Can't bump. Items can't take a deadline. *Provisional: Liam to confirm.*
- **The bump sheet's cost line counts bumps used before this one** ("2 of 3 bumps used" means this bump is the third). A repeat also gets a line for its window, "Until the end of its week (Sun 18 Oct)", or "Can bump until Wed 14 Oct, before it's next due" when its next occurrence comes first. *Provisional: Liam to confirm.*
- **A skipped row** shows its title greyed, "Skipped today" under it and a skip icon. Tapping it still completes it. Past days have no long-press menu. *Provisional: Liam to confirm.*
- **Deleting a one-off is confirmed too**, and the sticky note's title carries an icon per list (sun, checklist, moon), so the list reads in greyscale. *Provisional: Liam to confirm.*
- **The ↻ marks and the weekly count include the evening list**, though the ring and calendar circles still show only morning and day (three segments are step 4). *Provisional: Liam to confirm.*
- **The widget's bump doesn't ask you to retype** (a widget can't take text), as in 2a. *Provisional: Liam to confirm.*
- **Settings → Edit Lists replaces Edit Morning Routine.** Settings is now Lists (Edit Lists) · Daily (Add Daily Tasks) · Bumping (Retype to bump) until step 3 rebuilds it. *Provisional: Liam to confirm.*

## 2026-10-11 (evening): controls, flip times, calendar, greyscale, vault link (grilling for steps 2b–6)

**Working rules for the overnight run:** stacked PRs, nothing merged until Liam's phone check. An unsettled question takes the recommended default, recorded here as *provisional: Liam to confirm*. Anything that risks his data stops that step. Every UI and UX decision follows **Apple's Human Interface Guidelines**.

**2b: controls**
- **Edit lists:** one screen (Settings → Edit lists) with a Morning / Day / Evening segmented switch. It lists that list's recurring items, which you can add, reorder, and tap to edit: title, repeat (Apple-style picker), bump limit (non-daily items only), delete.
- **The flip button** on the sticky note cycles Morning → Day → Evening → Morning. The app still picks the list automatically by time (step 3).
- **Row actions:** tap and the existing swipe stay as they are (complete). A **long-press menu** carries everything else, as each row allows: Skip today (recurring items; tap again to undo), Bump (one-offs and less-than-daily items, within their limits), Edit, Delete.
- **The bump sheet:** "Bump to tomorrow", with what the bump costs ("2 of 3 bumps used", or the deadline). With **Retype to bump** on (the default), the title field starts empty with the old title as a faint hint; you must type something and may change it. With it off, the field is pre-filled.
- **Adding a one-off:** the existing "must happen today" button next to the add field opens a bigger options menu (tap or long-press): must happen today (can't bump), deadline date, bump limit (default up to 3 days).
- **Bump marks:** a bumped day gets a small **↻** badge on its ring cell and calendar day, and the header shows "N bumps this week" under the streaks. A bumped task shows just **"Bumped 2×"** (the link to the original stays in the data).

**3: flip times and settings**
- **The morning ends** either "When everything's done or skipped" or "At a set time". The unused wake-up window mode is removed.
- **With no set time,** the morning **streak** counts until **12:00**. The list itself flips only when you're done.
- **Evening** starts at **21:00** by default (changeable, or Off) and runs until midnight, with its own streak. Once complete, it stays showing as done. The day list sits between morning and evening.
- **Settings** is a native grouped list with sections: Lists (Edit lists) · Morning (how it ends, the time) · Evening (start time or Off) · Bumping (Retype to bump).
- **Each day stores the cutoff it had** when first opened.

**4: calendar**
- **Range:** from the earlier of the first entry's month and the current month, through the **next 12 months**.
- **Future days** show as plain dates (no empty progress circles), with a small dot when something is planned. Tapping a day opens it on Home, where you can add tasks.
- **Monday-first weeks** (locale). It opens on the current month.
- **Each day's circle** has up to three segments (morning, day, evening), showing only the lists in use.

**5: greyscale**
- **Colours stay, and every state also gets a shape:** done = filled with ✓ · partial = half-filled · missed = empty with × · nothing due = dashed outline · bumped = ↻.
- **Bumped tasks** show "↻2" in bolder text instead of a colour scale.

**6: vault link**
- **Access:** a fine-grained GitHub token, limited to **lratcliffe1/Obsidian** with contents read and write. Liam creates it and pastes it in once; it's stored in the Keychain.
- **A new vault area, `7 Projects/StickyNotes/`.** Its README covers the app, both APIs, the routines and SideStore. It also holds `tasks.json` (vault → app) and `habits/YYYY-MM.json` (app → vault). It gets a row in the vault's area table.
- **Now.md into the app:**
  - A routine fires on every push that changes Now.md, plus the 07:00 brief as a fallback. It reads only the diff since its last run, decides what belongs in the app, and rewrites `tasks.json`: the desired set of app tasks (today and future), with stable ids, dates, deadlines and bump limits.
  - The app fetches it on open, on returning to the foreground, during background refresh and from the widget. It reconciles by id: adds new tasks, updates changed ones unless done, removes tasks gone from Now.md unless done, and never overwrites your ticks or bumps.
  - The 07:00 brief stays read-only apart from `tasks.json`.
- **Habits back to Obsidian:** the app writes each day's results per list to `habits/YYYY-MM.json`, at most one commit a day (batched, when it goes to the background). A Dataview view in the Operating manual shows the streaks.
- **Ticking a Now.md task in the app** records it. The next brief or session proposes removing it from Now.md, so Now.md's "done means deleted" rule stays with Claude, in context.
- **No Shortcuts or Siri actions** for now; Liam doesn't use Siri.

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
