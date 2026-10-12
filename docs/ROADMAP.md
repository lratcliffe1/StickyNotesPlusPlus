# Roadmap

**What this is for:** the agreed order of work, one step per branch and PR, with each step's status. **What must NOT go in here:** the decisions themselves (→ `DECISIONS.md`) or how to work (→ `../CLAUDE.md`).

Agreed with Liam on 11.10.2026. Each step is grilled, then planned and signed off, before it's built.

| Step | What | Status |
|---|---|---|
| **0** | **Verification harness**: CI unit tests, simulator screenshots in colour and greyscale, versioned schema, `CLAUDE.md` | Done 11.10.2026 (PR #3); checked on the phone |
| **CI** | **CI speed-up**: one build per workflow, module cache, robust simulator choice, screenshots on every push | PR #6, done 11.10.2026 |
| **1** | **Quick bug fixes**: the app stays on yesterday if left open overnight (jump to today on day change and on returning to the foreground; refresh at the cutoff); the never-miss-twice banner wording | PR #4, in review |
| **2a** | **Data model and rules (no visible change)**: Items (recurring, Apple-style repeats, three lists) and Occurrences (one per item per day, plus one-offs; done, skipped or bumped; bump limits; bump links; deadline). Added *alongside* the V1 tables in schema V2, with your data copied across once (flag set after the save). One shared write service for the app and widget. Streak rules from `DECISIONS.md` | PR #5; installed and approved on the phone 11.10.2026 |
| **2b** | **Visible controls**: Edit list screens (all three lists, repeat and bump-limit pickers), skip, the bump flow (swipe, retype toggle with an editable title, link to the original), the "bumped" mark in the ring and calendar, bumps this week | PR #7, built and reviewed overnight 11.10.2026; waiting for the phone check |
| **3** | **Flip times and settings**: how the morning ends (a set time, or when everything is done or skipped, with its streak until 12:00), the evening from 21:00 (or Off) with its own streak, a grouped Settings screen, each day keeps the rules it had | PR #8, built and reviewed overnight 11.10.2026; waiting for the phone check |
| **4** | **Calendar rewrite**: SwiftUI, from the earlier of the first entry's month and the current month through the next 12 months; Monday-first weeks (locale); plain future days with a dot when something non-daily is planned; up to three segments per day; fetch only what's visible | PR #10, built and reviewed overnight 11.10.2026; waiting for the phone check |
| **5** | **Greyscale design pass**: one shape per state (done ✓ filled · partly done half · missed empty × · nothing due dashed · bumped ↻), drawn by one component for the ring and the calendar; "↻2" on bumped tasks | PR #11, built and reviewed overnight 11.10.2026; waiting for the phone check |
| **6** | **Vault link**: the app imports `7 Projects/StickyNotes/tasks.json` (written from Now.md by two routines) and writes `habits/YYYY-MM.json` back, through the GitHub contents API with a fine-grained token in the Keychain; no Shortcuts or Siri actions for now. File formats: `VAULT-API.md` | PR #9, built and reviewed overnight 11.10.2026; vault side and routines live; waiting for the token and the phone check |
| **Fix 1** | **Fix round 1 (phone feedback)**: morning items added after the cutoff are a bonus (shown, never counted); calendar and ring arcs fill by the share done (a sliver minimum, misses at most 85%); "Must do" / "Due …" stay on ticked tasks; one `StickyNotes.ipa` in iCloud | Branch `fix-round-1`, stacked on step 6; in review 12.10.2026 |

**Known gap (from 2b, not fixed in fix round 1):** after the morning's cutoff, editing an undone morning item's repeat so it no longer falls today, or deleting it, removes today's open row, so the morning can dodge a miss. To be decided.
