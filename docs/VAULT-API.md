# Vault API: the two vault files

**What this is for:** the contract between this app and Liam's vault (step 6, "vault link"): the two files, how the app reads and writes them, and the rules it follows. The vault's `7 Projects/StickyNotes/README.md` documents the same formats for the routines. **What must NOT go in here:** the product decisions themselves (→ `DECISIONS.md`) or the token (it lives only in the iPhone's Keychain).

Copied from the step 6 contract; the notes marked *(as built)* say where the implementation pins down something the contract left open. Code: `Shared/Vault/`.

Both live in the vault repo `lratcliffe1/Obsidian` under `7 Projects/StickyNotes/`. The app reaches them through the GitHub contents API (`GET/PUT /repos/lratcliffe1/Obsidian/contents/<path>`, path segments percent-encoded: `7%20Projects/StickyNotes/tasks.json`).

## tasks.json (vault → app; written only by the routines)

```json
{
  "version": 1,
  "generatedAt": "2026-10-12T05:00:12Z",
  "sourceCommit": "a63a378f…",
  "tasks": [
    {
      "id": "deel-chase-victoria",
      "title": "Chase Deel if no answers (case #7612521)",
      "list": "day",
      "dayKey": "2026-10-14",
      "deadlineDayKey": "2026-10-14",
      "bumpLimit": { "kind": "untilDeadline" }
    },
    {
      "id": "tmb-huts-booking",
      "title": "Book TMB huts Days 1–5 (opens today)",
      "list": "day",
      "dayKey": "2026-10-15",
      "bumpLimit": { "kind": "cantBump" }
    }
  ]
}
```

- `version`: 1. The app ignores a file with a higher major version (status: "tasks.json is newer than this app").
- `sourceCommit`: the vault commit whose `Now.md` this file reflects. The routines use it to diff; the app ignores it.
- `id`: stable, lowercase kebab-case, `[a-z0-9-]{1,64}`, unique in the file. *(As built: one invalid task, a duplicate id, an empty title or a malformed `dayKey` makes the whole file "bad": nothing changes, so a broken entry can never remove a task.)* **The same action keeps the same id across rewrites**, even if its title or date changes. A new id = a new task.
- `title`: ≤ 80 characters, plain text, imperative. *(As built: trimmed; anything past 80 characters is cut.)*
- `list`: `morning` | `day` | `evening`. Default `day` (also for a value the app doesn't know).
- `dayKey`: `YYYY-MM-DD` (Europe/Berlin), the day the task appears on. Today or later; the routine never writes past days (a past-dated action that's still open goes on today).
- `deadlineDayKey`: optional `YYYY-MM-DD`, ≥ `dayKey`.
- `bumpLimit.kind`: `cantBump` | `upToDays` (with `"days": N`, 1–14) | `untilDeadline` (requires `deadlineDayKey`) | `endOfWeek` | `unlimited`. Default when absent: `untilDeadline` if a deadline is set, else `upToDays` 3. *(As built: the same default for an unknown kind, or `untilDeadline` without a deadline; `days` is clamped to 1–14, missing means 3.)*
- Unknown fields are ignored (forward-compatible).

**App reconciliation (by id):**
- The app maps each `id` to a deterministic occurrence UUID (name-based UUID of `"vault-task:" + id`), and keeps a manifest `{id → occurrence UUID}` of tasks it imported, in the App Group defaults. **No schema change.** *(As built, after review: **one row per task per day**: the UUID is a name-based UUID of `"vault-task:<id>:<dayKey>"` (SHA-256 in the version 5 layout, as `OccurrenceID`), and the manifest (`vault_manifest_v2`) maps each id to its rows by day, plus a fingerprint of the task at its last import. It is written only after the store has saved, under a lock (below).)*
- **New id** → add a one-off on `dayKey` (or today, if `dayKey` is past) with the title, deadline and bump limit.
- **Known id, row still open and never bumped** → update title, list, day, deadline and bump limit. *(As built: **rows dated before today are history and never change.** With T = the task's day, or today if that is past:*
  - *T's row exists and is open and never bumped → it takes the file's title, list, deadline and bump limit when the file's task changed since the last import (so an edit made in the app lasts until Now.md changes it). Its day never changes.*
  - *T's row was imported and deleted in the app → it stays deleted.*
  - *No row at T → one is added, unless the task is **settled**: it settles on the day of its latest done, skipped or bumped row, or of a row deleted in the app (`settledOn`). The routines carry a still-listed action forward to today, and a ticked task stays in Now.md until a later session deletes it, so a settled task stays settled when the file re-dates it to today or earlier. It is scheduled again (`scheduledFor`) only by an explicit future date in the file, or by leaving the file and coming back, and `scheduledFor` is set to that day (earlier or later than before); a task scheduled for a later day that the file now dates today or earlier has `scheduledFor` brought back to today. A settling on or after it wins again. A bumped chain owns its own future. An OPEN row left on a past day doesn't settle the task: it stays as that day's miss, and today gets a fresh row.*
  - *When T has a row, any other open, never-bumped row of the task dated today or later is removed (the task moved).)*
- **Known id, row done, skipped or bumped** (or any bumped copy in its chain is done) → never touched. Ticks and bumps always win. *(As built: a bumped chain owns its own future: no row is added next to it. A task back in the file for a later date than its done row gets a new row.)*
- **Id gone from the file, row still open and never bumped** → removed. Done or bumped → kept. *(As built: only rows dated today or later are removed; past rows always stay.)*
- *(As built)* **A row imported and then deleted in the app** stays deleted. One-offs typed in the app are never touched. An existing row is never inserted again (fetched by id first), so a tick can't be reset. A task is never forgotten while it is listed (its rows older than 62 days leave the manifest, and any settling among them is kept in `settledOnTrimmed`, so un-ticking a row more than 62 days old doesn't unsettle the task); one gone from the file is forgotten 62 days after it left (its rows stay in the store). `vaultTasksDone` lists a task at most once per day.
- *(As built)* **One import at a time:** the manifest read, the store writes and the manifest write happen under `flock` on `vault-reconcile.lock` in the App Group container; the app waits up to 1 s, the widget not at all, and either skips the import if the other holds it. Without an App Group container the widget never imports and the app imports alone; if the lock file can't be opened, nothing is imported and the status reads "Imported tasks: couldn't lock". The import runs in a fresh `ModelContext` (never the app's main context), so rows the widget changed are read from the store; Home re-reads after it. **An unreadable manifest** is rebuilt from the store: for each task in the file, the rows whose ids are `vault-task:<id>:<day>` for days from 62 days ago to 60 days ahead (one fetch); ticks and bumps settle their tasks again, but app deletions, ticks older than the 62-day window and last-import fingerprints are lost, so the status reads once "Imported tasks: rebuilt; a task done or deleted in the app may come back once".
- A bad file (invalid JSON, wrong version) changes nothing and shows a calm status in Settings.

**How the app fetches it** *(as built)*: `GET` with `Accept: application/vnd.github.raw+json`, `Authorization: Bearer <token>`, `X-GitHub-Api-Version: 2022-11-28`, and `If-None-Match` with the ETag of the last good file. A 304 reconciles the stored copy of that file again (so a new day still gives still-open tasks a row today). The ETag and the copy are stored only after the store saved. When: on launch and on returning to the foreground (after the habits write for an unsent yesterday), in a `BGAppRefreshTask` (`com.liamratcliffe.Sticky-Notes-Sticky-Life.vault-refresh`), and from the widget's timeline (only when the token is in the shared keychain group, at most every 15 minutes, 5-second requests, one request: no repo check on a 404; the widget changes the status only on success or a token failure).

**Status line** (Settings → Vault link), from the answers: Not set up · Connected (token just saved) · Tasks updated <time> · No tasks file yet (404, and the token can see the repo) · Token not accepted (401; 403 that isn't rate limiting; 404 on the repo itself) · Token expired (401 after the expiry date GitHub sends in `GitHub-Authentication-Token-Expiration`, or a 401 that says "expired") · Offline (no answer) · tasks.json is newer than this app · tasks.json couldn't be read · Imported tasks: rebuilt; a task done or deleted in the app may come back once (manifest unreadable) · Imported tasks: couldn't lock · GitHub didn't answer (<code>) (rate limits, 5xx).

## habits/YYYY-MM.json (app → vault; written only by the app)

```json
{
  "version": 1,
  "month": "2026-10",
  "updatedAt": "2026-10-12T21:40:03+02:00",
  "streaks": { "morning": 12, "day": 3, "evening": 0 },
  "days": {
    "2026-10-12": {
      "morning": { "status": "complete", "done": 6, "skipped": 0, "bumped": 0, "total": 6 },
      "day":     { "status": "missed",   "done": 2, "skipped": 1, "bumped": 1, "total": 5 },
      "vaultTasksDone": [
        { "id": "deel-chase-victoria", "title": "Chase Deel if no answers (case #7612521)", "doneAt": "2026-10-12T10:02:00+02:00" }
      ]
    }
  }
}
```

- One file per calendar month; `days` keyed by `dayKey`. A day appears once it is over, or is today at write time (today may be partial and is rewritten next time).
- `status` uses the app's own rule (`ListRules.dayLooks`): `complete` | `missed` | `neutral` | `open` (today, not yet decided). Lists not in use are omitted. *(As built: a list is in use on a day if it has rows that day, or a miss judged from what was due on a day nobody opened. `neutral` = rows, but nothing counted (all skipped). Today is `open` until it is complete. `done`, `skipped`, `bumped` and `total` count that day's rows, so a day nobody opened is `missed` with `total` 0. The example's `"evening": neutral` line is gone for that reason.)*
- `streaks`: the current streak per list at `updatedAt`.
- `vaultTasksDone`: imported `tasks.json` tasks ticked that day. *(As built: always present, possibly `[]`; a task bumped and then ticked counts on the day it was ticked, with that row's title.)* **The next brief or session proposes removing them from Now.md** (Now.md's "done means deleted" stays with Claude).
- **Write policy:** at most one commit a day, when the app goes to the background, after the day's first background-ing past the morning (or the next day's first launch, for the previous day). The app GETs the file's `sha`, merges its days into it (its own days win), and PUTs with that `sha`. On `409/422` (sha conflict) it refetches once and retries once; otherwise it gives up until the next day.
- Commit message: `StickyNotes: habits YYYY-MM-DD`.
- *(As built, `VaultHabitsGate`)*: the gate is the day of the last commit (`vault_habits_last_commit_day`).
  - **Going to the background** after today's morning has ended (its set time, or 12:00), with no commit today: writes this month through today (today `open`).
  - **Launching or returning to the foreground** when yesterday had no commit at all: writes through yesterday ("StickyNotes: habits <yesterday>"), before the day's import. That uses today's commit; today goes out with tomorrow's.
  - **A month end:** if the last commit was in an earlier month, that month's file is finished first, through its last day ("StickyNotes: habits <last day>"), then the current one: the one case with two commits in a sync (one per file). Months with no commit at all in between aren't written.
  - **Already there:** if the vault's file already equals what would be sent, apart from `updatedAt`, nothing is PUT and the day counts as sent (a write whose answer was lost isn't committed twice). A tick made after such a lost write changes the content, so that day can then get a second commit.
  - The write runs inside a `beginBackgroundTask` window. Only a success or a second conflict closes the day; offline, auth and server errors leave it open for the next chance. A 401/403 on the write shows "Token not accepted" (e.g. a read-only token). `GET` and `PUT` use `Accept: application/vnd.github+json`; the body is `{message, content (base64), sha}` (no `sha` when the file is new).

## Dataview (Operating manual)

DataviewJS (enabled in this vault) reads the current month's JSON with `dv.io.load("7 Projects/StickyNotes/habits/" + month + ".json")`, then renders the streaks and a last-14-days table. No `streaks.md` is needed.

## The token and signing *(as built)*

- A fine-grained GitHub token for `lratcliffe1/Obsidian` only, Contents read and write. Liam pastes it in Settings → Vault link → GitHub token → Paste → Save (the setup note is on his Desktop, "StickyNotes token setup"). It is stored only in the Keychain (`KeychainVaultTokenStore`: a generic password, service `com.liamratcliffe.StickyNotes.vault`, readable after the first unlock, this device only). Never in UserDefaults, a file, a log or a screenshot.
- **Sharing it with the widget:** the item is saved with the App Group identifier (resolved from `ALTAppGroups`, as for the store) as its `kSecAttrAccessGroup`. On iOS an app group is a valid keychain access group for any app that has the `com.apple.security.application-groups` entitlement, so no `keychain-access-groups` entitlement is added.
- **What `build-ipa.yml` signs:** it archives unsigned, then ad-hoc signs the widget and the app with the existing entitlements files, which carry only `com.apple.security.application-groups`. SideStore then re-signs with Liam's free account, renaming the group and listing it under `ALTAppGroups`. Nothing in that path changes for step 6; a `keychain-access-groups` entitlement (which needs the team-ID prefix SideStore's free signing controls) was deliberately not added.
- **If iOS refuses the group** (`errSecMissingEntitlement`), the token is saved in the app's default group instead and `vault_token_location` says `appOnly`: the widget then never fetches and shows the app's last import, and Settings says so. This can only be confirmed on the phone (the simulator and the unit tests never touch the real Keychain).
