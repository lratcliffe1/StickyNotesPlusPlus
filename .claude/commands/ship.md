# Ship a build to Liam's phone

Builds a Release `.ipa` on GitHub and puts it where Liam's phone can reach it. Liam does the install; you never touch his phone.

**Branch:** `$ARGUMENTS` (empty = `main`).

1. `gh workflow run "Build IPA for SideStore" --ref <branch>`, then find the run (`gh run list --workflow build-ipa.yml --limit 1`) and `gh run watch <id> --exit-status`.
2. `gh run download <id> -n StickyNotesPlusPlus-ipa -D ~/Downloads/StickyNotesPlusPlus-ipa` (delete the old `.ipa` there first).
3. Check that the build carries the App Group entitlement, so the widget can share data: unzip it to a scratch dir and run `codesign -d --entitlements :- Payload/*.app`. It must list `com.apple.security.application-groups`.
4. Copy it to iCloud Drive: `cp ~/Downloads/StickyNotesPlusPlus-ipa/StickyNotesPlusPlus.ipa "$HOME/Library/Mobile Documents/com~apple~CloudDocs/"`.
5. Tell Liam:
   - **Install:** with LocalDevVPN connected, open SideStore → My Apps → **+** → iCloud Drive → `StickyNotesPlusPlus.ipa` → "Register App ID for each extension".
   - **Check:** exactly which states to test on the phone, taken from the PR's **Not verified** list.

Never edit his data, and never ask for his Apple ID. If an install fails with an App ID limit (a free account gets 10 new IDs a week), say so and stop.
