# Roadmap

**What this is for:** the agreed order of work, one step per branch and PR, with each step's status. **What must NOT go in here:** the decisions themselves (→ `DECISIONS.md`) or how to work (→ `../CLAUDE.md`).

Agreed with Liam on 11.10.2026. Each step is grilled, then planned and signed off, before it's built.

| Step | What | Status |
|---|---|---|
| **0** | **Verification harness**: CI unit tests, simulator screenshots in colour and greyscale, versioned schema, `CLAUDE.md` | Done 11.10.2026 (PR #3); checked on the phone |
| **1** | **Quick bug fixes**: the app stays on yesterday if left open overnight (jump to today on day change and on returning to the foreground; refresh at the cutoff); the never-miss-twice banner wording | PR #4, in review |
| **2a** | **Data model and rules (no visible change)**: Items (recurring, Apple-style repeats, three lists) and Occurrences (one per item per day, plus one-offs; done, skipped or bumped; bump limits; bump links; deadline). Added *alongside* the V1 tables in schema V2, with your data copied across once (flag set after the save). One shared write service for the app and widget. Streak rules from `DECISIONS.md` | Signed off 11.10.2026, in progress |
| **2b** | **Visible controls**: Edit list screens (all three lists, repeat and bump-limit pickers), skip, the bump flow (swipe, retype toggle with an editable title, link to the original), the "bumped" mark in the ring and calendar, bumps this week | Plan after 2a |
| **3** | **Flip time + skip + settings screen**: an optional flip time (none = flips when everything is done or skipped); "skip today" on an item; the missing settings screen for the cutoff or wake-up window; each day stores its own deadline | Not started. Grill first |
| **4** | **Calendar rewrite**: SwiftUI, starting at whichever is earlier of the first entry's month and the current month, through the current month; Monday-first weeks (locale); no clutter for future days; fetch only what's visible | Not started |
| **5** | **Greyscale design pass**: every state readable without colour. First targets, from the step 0 screenshots: the 7-day ring and the calendar days, where full and partial days come out the same grey | Not started |
| **6** | **Vault link + Shortcuts**: the app reads a `today.json` written by Claude from `Now.md`, and writes habit completions back to the private vault repo (GitHub API, a token scoped to that repo); App Intents for "add task" and "log routine item" | Not started. Grill first |
