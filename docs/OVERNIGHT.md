# StickyNotes++ overnight run: handoff (written 2026-10-11 ~16:30)

You are the **coordinator** of an approved, autonomous overnight run on Liam's iOS habit app, StickyNotes++. Liam has gone to bed. He answered every design question beforehand and said "go". Your job is to drive the remaining roadmap through builder agents, verification and blind review, and leave him a clean morning hand-off. **Do not ask him anything**; follow the rules below for open questions.

## Where things are

- **App repo:** `~/code/StickyNotesPlusPlus` (GitHub `lratcliffe1/StickyNotesPlusPlus`). Read its `CLAUDE.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`, `.claude/agents/checker.md`, `.claude/commands/verify.md` and `.claude/commands/ship.md` before anything else.
- **Tonight's decisions:** `~/code/SN-DECISIONS-EVENING.md`. Your **first commit** on the 2b branch prepends it to the top of `docs/DECISIONS.md`, and adds this line to `CLAUDE.md` → "Rules that bind": **"Apple's Human Interface Guidelines govern every UI and UX decision: native controls, standard gestures, system fonts and spacing, Dynamic Type and accessibility labels."** In the same commit, copy this file to `docs/OVERNIGHT.md` and keep its *Progress log* below up to date as you go.
- **Liam's vault** (Obsidian, git repo, GitHub `lratcliffe1/Obsidian`, private): `/Users/liamratcliffe/Desktop/Obsidian`. Only step 6 touches it. Read its root `CLAUDE.md` first (areas, link conventions, "Adding an area"). Vault commits go straight to `main` (that's the vault's convention): `git pull` first, commit with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, push.

## The state at handoff

- **Merged to main:** step 0 (PR #3).
- **Open, stacked, all verified:** **#4** (step 1, base main) ← **#5** (step 2a, base `step1-bug-fixes`). Liam installed and approved 2a on his phone. #4 waits for his overnight check (the app left open on Sunday should show Monday). **Never merge anything.**
- **`ci-speedup`** (stacked on 2a): **done and green** (de2f673), open as **PR #6**, base `step2a-model`. Start the 2b branch from `origin/ci-speedup`. CI now runs both workflows on every push, with concurrency cancel. Simulators are picked by `scripts/ci-simulator.sh` (iOS 18.5). Expect about 5 min for Quality and 6–8 min for Screenshots.
- **Liam's phone runs the 2a build** (schema V2). No downgrade below V2, ever.

## Order and rules

**Order:** ~~CI~~ (done, #6) → **2b** → **3** → **4** → **5** → **6**. Each step gets **its own branch stacked on the previous one**, and **its own PR** (base = the previous step's branch). Never push to main, and never merge.

**Open questions:** take the recommended default, note it in `docs/DECISIONS.md` as *"provisional: Liam to confirm"*, and carry on. **Anything that risks Liam's real data** (a migration that could fail to open his store, data loss) **stops that step**: write it up, and move to the next step only if it doesn't depend on that one.

**Per step, the same loop:**
1. Write the step's plan into the PR description first: its goal, what's in scope (from `DECISIONS.md`), and its acceptance checks.
2. A **builder agent** (general-purpose; brief it to read CLAUDE.md, DECISIONS.md and the relevant code, and give it the exact scope, conventions and done criteria) implements it. Batch the work, and run builders in the background.
3. **CI is the only compiler (no Xcode on this Mac).** Push, then wait for the runs (poll `gh run view <id> --json status,conclusion`, because `gh run watch` can exit early), read `--log-failed`, and fix. Fresh runners sometimes list no iPhone simulator; `scripts/ci-simulator.sh` from the CI branch handles that.
4. **Look at the screenshots yourself**, in colour **and** `-grey`: `gh run download <id> -n screenshots -D <new dir>`, `sips -Z 700`, then Read the PNGs. Add harness scenarios in `UITestHarness` plus rows in `scripts/screenshots.sh` for every new state the step creates (the bump sheet, the long-press menu, Edit lists, Settings, evening, the calendar with future days, greyscale shapes, imported tasks, and so on).
5. **Blind review:** the `checker` agent if it's available in this session (it is, if this chat was started in the app repo), otherwise a general-purpose agent told to read and follow `.claude/agents/checker.md`. Give it the plan and the diff ref, **never the builder's summary**. Fix every HIGH and MED finding, then run a focused re-review of the fixes. LOW findings get fixed if cheap, otherwise listed in the PR.
6. **Update the PR body** with **Verified** and **Not verified** lists (CI run IDs, tests by name, what you saw in which screenshot), plus anything deferred or provisional.
7. Update `docs/ROADMAP.md` (the step's status) and this file's progress log, then move on.

**Builders lie by accident.** Re-check every claim (run IDs, test counts with `grep -c "' passed on"` and `"' failed on"`, screenshots) before relaying it.

## Lessons from today (don't relearn them)

- **The simulator's status-bar clock** accepts "08:15" but rejects afternoon times. It's cosmetic, and the app's own time in the shots is right.
- **Unopened days with items due are misses, not neutral.** The rule is `ListRules.dayLooks`, and the streak, ring and calendar must all use it.
- **Item-occurrence ids are deterministic** from (itemID, scheduledDayKey). Keep it that way.
- **Schema changes:** a new version plus a migration stage, and the pinned shape tests (`testVersionOneShapeIsPinned`, `testVersionTwoShapeIsPinned`) are never edited to make them pass. If 2b–6 need model changes, add V3 carefully (additive, lightweight where possible) and pin it.
- **The App Group is resolved via `ALTAppGroups`** (SideStore). Never hardcode it.
- **The widget's `try?`** fails silently. Keep the widget's work small: today plus items only.
- **Test-only code stays in `#if DEBUG`.**

## Step 6 specifics (the vault link)

All the decisions are in DECISIONS.md, in the 2026-10-11 evening entry. Extra details:
- **Vault area:** create `7 Projects/StickyNotes/` per the vault's "Adding an area" rule:
  - a README with **What this is for** / **What must NOT go in here** headers, documenting the app, SideStore install and renewal, rebuilding (the `Build IPA for SideStore` workflow), both APIs (the `tasks.json` schema and the `habits/YYYY-MM.json` schema, with examples), both routines, and links to the repo's DECISIONS and ROADMAP;
  - a row in the root `CLAUDE.md` area table, and an entry in `7 Projects/7 Projects.md`.
  - Link the area from `4 Mental Models/Operating manual.md`, with a Dataview streak view reading the habits JSON. Dataview can't read JSON directly, so it's acceptable to have the app also write a small `habits/streaks.md` with inline fields (e.g. `morning-streak:: 12`) for Dataview. Choose and document it.
- **The token:** the app needs a GitHub fine-grained personal access token limited to `lratcliffe1/Obsidian`, with Contents read and write, kept in the Keychain and entered in Settings → Vault link. Write `~/Desktop/StickyNotes token setup.md` with click-by-click instructions (github.com → Settings → Developer settings → Fine-grained tokens → …, the expiry choice, and pasting it into the app). **Never ask for or handle the token yourself.**
- **The app side:**
  - fetch `tasks.json` via the GitHub contents API, using ETag / If-None-Match, on launch, on returning to the foreground, during background refresh (BGAppRefreshTask) and from the widget timeline;
  - reconcile by id: add new tasks, update undone ones, remove undone ones that are gone, never overwrite ticks or bumps;
  - write the habits file at most once a day, batched, when going to the background, through the contents API with the sha;
  - handle offline, auth failure (a visible but calm status in Settings) and conflicts (refetch the sha and retry once).
- **Routines** (use the `RemoteTrigger` tool; never print secrets):
  - **Existing morning brief:** `trig_01QRQrYSGcpzxW3ZXvRpYRqW`, which runs daily at 05:00 UTC on repo lratcliffe1/Obsidian, environment `env_017gENMBEUch9mtkSpL7B3xq`, Gmail connector `5044b44d-6856-4e1c-b3fb-73f7e137f1dc`, push only. Read it with `get`, then **update** its prompt so it also refreshes `7 Projects/StickyNotes/tasks.json` (the same rules as below) and may commit and push **that file only**. Keep everything else it does unchanged.
  - **New routine "StickyNotes: sync Now.md → tasks.json":**
    - **Setup:** the same repo and environment, no connectors.
    - **Trigger:** `create_webhook_trigger` on GitHub **push** to `lratcliffe1/Obsidian`, `main`, filtered to changes to `7 Projects/Life admin/Now.md` if the filter supports paths. If it doesn't, the routine itself exits early when Now.md is unchanged since `tasks.json`'s `sourceCommit`.
    - **What it does:** reads the git diff of Now.md since that commit, decides with judgement which actions belong in the app (dated actions due today or in the future, plus clear next actions, each with a stable id), rewrites `tasks.json` with the new `sourceCommit`, commits and pushes only that file.
    - **Loop guard:** a push that only changes `tasks.json` or `habits/` must not re-trigger work.
    - **Notifications off,** unless something fails.
  - Document both routines in the area README.

## Morning hand-off (before you stop)

1. **One combined build:** run `Build IPA for SideStore` on the **top of the stack**. Check it has the App Group entitlement and no harness string (`strings … | grep -c uiScenario` should give 0), and copy it to `~/Library/Mobile Documents/com~apple~CloudDocs/StickyNotes-overnight-<shortsha>.ipa`.
2. **The report:** write `~/Desktop/StickyNotes overnight report.md`, short and plain English (Liam is ill and in greyscale):
   - per step: done or parked, PR link, what was verified, **what to check on the phone**;
   - every provisional decision;
   - the morning checklist, in order: the step 1 overnight check → install the IPA (the exact filename and size) → the per-step checks → create the token (link to the setup note) → paste it → watch the first `tasks.json` import.
   - Commit nothing to the vault for the report itself.
3. **The order to merge PRs once he's happy:** #4 → #5 → ci-speedup → 2b → 3 → 4 → 5 → 6, each retargeted to main after the previous one merges.

## Progress log (keep updated)

- 16:30: handoff written.
- 16:55: CI speed-up done, PR #6 open. The next step is 2b, branched from `origin/ci-speedup`.
- 16:57 (new coordinator chat): read the handoff and the repo docs; branched `step2b-controls` from `origin/ci-speedup`; first commit lands the evening decisions, the HIG rule and this file.
