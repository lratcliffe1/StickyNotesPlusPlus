# Decisions

**What this is for:** product rules Liam has decided, dated, newest first. Code and tests follow these. When a rule changes, add a new entry that names the one it replaces; never edit an old entry. **What must NOT go in here:** plans and status (→ `ROADMAP.md`).

## 2026-10-11 (overnight, step 5): greyscale, provisional calls

Taken while building step 5 with Liam asleep (see the working rules in the evening entry below). Each is *provisional: Liam to confirm*.

**From the plan**
- **Today, not yet decided,** is half-filled if anything is done, otherwise a plain outline (not dashed, no ×), since it isn't missed yet. A list is undecided until its streak deadline: the morning until its set time (12:00 with no set time), the day and evening lists until midnight. Once today's morning is past its deadline unfinished, it's drawn as the miss it is (with ×). *Provisional: Liam to confirm.*
- **In a 2–3 segment calendar circle,** each segment takes the same shapes at small size (filled / half / empty / dashed); the ✓ and × appear only on one-list calendar days, as a small badge at the bottom right (the date fills the middle; the ↻ badge stays top right), and in the middle of every 7-day ring day. *Provisional: Liam to confirm.*

**Made while building**
- **One mapping, `DayMark`** (`Shared/Calendar/DayMark.swift`), drawn only by `SegmentedDayRing`, driven by the streak status first: done (complete) = filled · a miss with something done = half-filled · a miss with nothing done = empty · still open today = half-filled or empty, with no × · nothing due = dashed. So on a decided day only a filled segment is done. *Provisional: Liam to confirm.*
- **The day's ✓ or ×:** ✓ when every list in use is done or had nothing due, and at least one is done (a day before the evening list existed, or with nothing on the day list, keeps its ✓); × when any list is a miss; none otherwise. *Provisional: Liam to confirm.*
- **Half-filled is always exactly half** of the segment, with a solid edge where the fill stops, whatever the share done (1 of 6 or 5 of 6). This replaces step 4's arcs that filled along their length by the share done, which were faint in greyscale at small shares and drew a late finish as done. The exact percentage is on Home and in VoiceOver. *Provisional: Liam to confirm.*
- **A list done late** (everything done, after the morning's cutoff) is half-filled with a ×, like any other miss with something done, not filled: it still cost the streak. VoiceOver says "missed, all done after the cutoff". *Provisional: Liam to confirm.*
- **An open calendar reads again at the next boundary** (the morning's deadline, the evening's start, midnight: the same `DayRules.nextBoundary` as Home's timer), so today's morning stops showing as open once its deadline passes. *Provisional: Liam to confirm.*
- **The ↻ badge moves clear of the ring:** above the circle in the 7-day ring, and further out at the top right of a calendar day (the ✓/× badge mirrors it at the bottom right), so it never hides the morning segment's shape. *Provisional: Liam to confirm.*
- **Colours stay** (red through green by the share done), darker so they keep contrast against the track in greyscale. *Provisional: Liam to confirm.*
- **"↻2"** sits at the right of a bumped task's row, a bold arrow and count (VoiceOver: "Bumped 2 times"), replacing the "Bumped 2×" subtitle. The strike-through on day-list rows is now the list's colour instead of a colour scale by bump count. *Provisional: Liam to confirm.*
- **A frozen streak** shows a snowflake after its count (it was only blue, and smaller). *Provisional: Liam to confirm.*
- **Home on a future day** shows "—" and an empty bar, like a neutral day, not "0%": nothing can be done on it yet. *Provisional: Liam to confirm.*
- **VoiceOver words follow the shapes:** the verdict comes first, so a past day partly done says "missed, 50 percent done" (it said "missed"); today with nothing done says "nothing done yet"; today's morning past its deadline is a miss. A day's lists are joined with semicolons ("Monday 12 October: morning done; day missed, 50 percent done; bumped"), so each reads as one item. *Provisional: Liam to confirm.*
- **Left as they are:** the progress bar's colour per list (the list is named by the title and icon beside it), the banner's orange triangle (the icon and bold text carry it), Settings, Edit Lists and the bump sheet (no meaning in hue alone), and the widget (it draws no day states; its bump button is an icon). *Provisional: Liam to confirm.*

## 2026-10-11 (overnight, step 4): calendar, provisional calls

Taken while building step 4 with Liam asleep (see the working rules in the evening entry below). Each is *provisional: Liam to confirm*.

**From the plan**
- **A day's circle is one ring split into equal arcs** (2 or 3), clockwise from 12 o'clock in Morning → Day → Evening order; a single list in use is a full ring. Each arc fills along its length as far as that list is done, so progress reads as length as well as colour. The 7-day ring uses the same component, evening included. *Provisional: Liam to confirm.*
- **The future-day dot** shows when a one-off is planned that day (or a copy has been bumped onto it), or a recurring item that isn't every-day falls due (weekly, monthly…). Daily items don't count: they would put a dot on every day. (Replaces the plan's call, where daily items counted too; changed after review.) *Provisional: Liam to confirm.*
- **Home on a future day** shows that day's one-offs and, under "Repeats · can be done on the day", the recurring items due then, read-only until the day: completing is disabled; adding, editing and deleting one-offs are allowed. Recurring items get rows only on the day itself, as before. Nothing on a future day can be completed, skipped or bumped, in `ListService` as well as on screen (a bump counts as done, so it would settle the day in advance); a future row's menu has only Edit… and Delete, on one-offs, and a recurring item's copy bumped onto tomorrow waits for tomorrow. *Provisional: Liam to confirm.*

**Made while building**
- **"Lists in use"** is the same rule as the header's evening streak (`ListService.isInUse`: any item or occurrence, ever), so every day's circle has the same segments; a list with nothing on a given day shows a dashed segment that day. Days before the first entry are plain dates. *Provisional: Liam to confirm.*
- **On a future day, the streaks stay as of today** (they were counting the days to come as misses, showing 0). *Provisional: Liam to confirm.*
- **"Through the next 12 months"** means through the current month plus 12 (October 2026 → October 2027). A one-off added beyond that isn't shown until its month comes into range. *Provisional: Liam to confirm.*
- **Nothing counted for a list that day** is a dashed outline arc; missed with nothing done is an empty outlined arc; the 7-day ring puts a ✓ in a day where every list in use is complete (the streak's verdict, so a late morning gets none). Step 5 replaces this with the full shape vocabulary. *Provisional: Liam to confirm.*
- **Today** is the date on a filled disc in the calendar (an underlined, bold weekday letter in the ring); the day open on Home is tinted. Future days in the 7-day ring (when Home is on a future day) are drawn like the calendar's: no circle, a dot if something is planned. *Provisional: Liam to confirm.*
- **The calendar has a standard navigation bar** ("Calendar", back, and a "Today" button that scrolls to the current month), replacing the floating Today capsule. *Provisional: Liam to confirm.*
- **Fetching:** each month is fetched when it first scrolls into view, and again after the app returns to the foreground or the day changes while the calendar is open, from its first day minus the longest repeat period among the items (0 days with only daily items, a week for weekly, a month for monthly, a year for yearly), so a miss from an occurrence before the month that lands on a period end inside it still shows. The 7-day ring reads the same way for its seven days. Streaks still read each list's whole history. *Provisional: Liam to confirm.*
- **"N bumps in 7 days"** counts the ring's days up to today only, matching the ↻ marks (later days show none). *Provisional: Liam to confirm.*

## 2026-10-11 (overnight, step 3): flip times and settings, provisional calls

Taken while building step 3 with Liam asleep (see the working rules in the evening entry below). Each is *provisional: Liam to confirm*.

**From the plan**
- **On upgrade, the morning ends "At a set time", 09:00**, today's behaviour, so nothing changes until Liam picks. The evening starts at 21:00. *Provisional: Liam to confirm.*
- **A morning with no set time stays the shown list until it's done or all skipped,** even after 12:00, as Liam decided ("the list itself flips only when you're done"); its streak still counts only until 12:00. Only the evening's start takes over from an unfinished morning. *(Replaces tonight's earlier provisional call that it flipped to the day list at 12:00.)*
- **A settings change never redecides today's morning.** The morning part of today's stored rules changes only while `now` is before both the old and the new deadline and the morning isn't complete; otherwise the change applies from tomorrow, and Settings says so ("Today keeps 9:00; this applies from tomorrow."). The evening start never decides a streak (the evening counts until midnight), so it changes today. Past days never change. *(Replaces tonight's earlier provisional call that a change applied to today as well.) Provisional: Liam to confirm.*
- **Each day's rules live in the App Group settings, not the store** (no schema change): stored the first time the app or widget reads the day, first read wins. Days before this build use the old 09:00 cutoff; a day nobody opened uses the nearest earlier stored day's rules. A saved wake-up window (never reachable in the UI) becomes "At a set time" at wake-up + duration. *Provisional: Liam to confirm.*

**Made while building**
- **An empty evening list doesn't take over:** from the evening's start, Home and the widget show the evening list only if it has something on it (done, skipped or open); with nothing on it the day list stays. *Provisional: Liam to confirm.*
- **A manual flip lasts until the next moment the list would change on its own** (a set time, the evening's start, or midnight; with no set time, 12:00 isn't one), then the automatic choice takes over again, so flipping to the day list at 08:00 doesn't hide the evening at 21:00. The flip carries its expiry time, so this holds even when the app was in the background as the boundary passed. A flip on a day other than today lasts until Home leaves that day. *Provisional: Liam to confirm.*
- **Finishing the morning moves to whichever list the time picks** (the day list, or the evening once it has started), not always the day list. *Provisional: Liam to confirm.*
- **Settings keeps "Add a Task on Another Day"** as a second row under Lists (it was its own "Daily" section in 2b), so nothing is lost; the plan's sections are otherwise as listed. The morning's two choices are inline rows with a checkmark ("Ends at a Set Time", "Ends When Everything's Done or Skipped"), so the long label never truncates and the choice reads in greyscale. *Provisional: Liam to confirm.*
- **The evening's Off is a toggle, "Switch to Evening List"**; off, Home never flips to the evening on its own, and the evening streak still counts until midnight. Its start time can be set from 12:00 to 23:45 (a start at 00:00 would make the whole day evening). *Provisional: Liam to confirm.*
- **The header shows the evening streak** (a moon and the count, under the sun and flame) once the evening list is in use, i.e. has any item or task. *Provisional: Liam to confirm.*

## 2026-10-11 (overnight, step 2b): controls, provisional calls

Taken while building step 2b with Liam asleep (see the working rules in the evening entry below). Each is *provisional: Liam to confirm*.

**From the plan**
- **Editing an item's repeat applies from today.** The old item ends and a new one starts today, or tomorrow if today's occurrence is already done, skipped or bumped, so past days are never recounted. A copy already bumped onto a later day stays with the old item and finishes its period. A bump-limit edit changes the item and today's open occurrence only. A title-only edit is a rename from today, as before, and a new title applies from today even when the repeat part starts tomorrow (today's done row takes it). An item that has already ended can't be edited or deleted again. *Provisional: Liam to confirm.*
- **Delete on a recurring row** deletes the item from today on (as in Edit lists), after a confirmation. *Provisional: Liam to confirm.*
- **Edit… on a one-off** edits its title, deadline and bump limit for that row only (not the rows earlier in its bump chain). On a recurring row it opens the item editor. *Provisional: Liam to confirm.*
- **"N bumps in 7 days"** (Liam said "N bumps this week") counts bump actions on the seven days the ring shows, across all three lists, so the number always matches the ↻ marks on screen. Hidden at 0. *Provisional: Liam to confirm.*

**Made while building**
- **Bumping is only in the long-press menu.** The one-tap bump button on day-list rows is gone, since bumping should never be a single tap. *Provisional: Liam to confirm.*
- **The add menu's bump limits** are Up to 1, 3 (the default) or 7 days, End of week, Until deadline, and Unlimited. Choosing Until deadline with no deadline opens the date picker. A deadline on its own leaves the limit as it is. The chosen options show in words under the add field, and reset after each add. *Provisional: Liam to confirm.*
- **An item's bump limit** (non-daily repeats only) is one of: Until its period ends (the default), Up to N days, Until the end of the week, Can't bump. Items can't take a deadline. *Provisional: Liam to confirm.*
- **The bump sheet's cost line counts bumps used before this one** ("2 of 3 bumps used" means this bump is the third). A repeat also gets a line for its window, "Until the end of its week (Sun 18 Oct)", or "Can bump until Wed 14 Oct, before it's next due" when its next occurrence comes first. *Provisional: Liam to confirm.*
- **A skipped row** shows its title greyed, "Skipped today" under it and a skip icon. Tapping it still completes it. Past days have no long-press menu. *Provisional: Liam to confirm.*
- **Deleting a one-off is confirmed too**, and the sticky note's title carries an icon per list (sun, checklist, moon), so the list reads in greyscale. *Provisional: Liam to confirm.*
- **The ↻ marks and the weekly count include the evening list**, though the ring and calendar circles still show only morning and day (three segments are step 4). *Provisional: Liam to confirm.*
- **The widget follows Retype to bump.** With it on, the widget's bump button opens the app on that task's bump sheet (if it can still be bumped) instead of bumping in one tap. With it off, the widget bumps in one tap, within the task's limits. *Provisional: Liam to confirm.*
- **A row whose item has ended** (deleted today, or replaced by a repeat change while today's row was already done, skipped or bumped) has no Edit… or Delete in its menu: without a link from the old item to its replacement, the app can't tell which item to edit. Skip and bump still work on the row. *Provisional: Liam to confirm.*
- **Sheets and menus act only on today or later.** A bump, skip, undo skip, one-off edit or delete left open past midnight does nothing to yesterday's row. *Provisional: Liam to confirm.*
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
