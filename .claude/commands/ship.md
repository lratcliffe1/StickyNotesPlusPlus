# Ship a build to Liam's phone

Builds a Release `.ipa` on GitHub and puts it where Liam's phone can reach it. Liam does the install; you never touch his phone.

**Branch:** `$ARGUMENTS` (empty = `main`).

1. `gh workflow run "Build IPA for SideStore" --ref <branch>`, then find the run (`gh run list --workflow build-ipa.yml --limit 1`) and `gh run watch <id> --exit-status`.
2. `gh run download <id> -n StickyNotesPlusPlus-ipa -D ~/Downloads/StickyNotesPlusPlus-ipa` (delete the old `.ipa` there first).
3. Check that the build carries the App Group entitlement, so the widget can share data: unzip it to a scratch dir and run `codesign -d --entitlements :- Payload/*.app`. It must list `com.apple.security.application-groups`.
4. Copy it to iCloud Drive as `StickyNotes.ipa`, overwriting the previous build: Liam keeps one file there. The build's branch and sha go in the commit or PR, not the filename; take the sha from the run, not your checkout (`gh run view <id> --json headSha -q '.headSha[0:7]'`). `cp ~/Downloads/StickyNotesPlusPlus-ipa/StickyNotesPlusPlus.ipa "$HOME/Library/Mobile Documents/com~apple~CloudDocs/StickyNotes.ipa"`, then read its size back from iCloud Drive (`ls -lh` on that path) to tell Liam.
5. Tell Liam:
   - **Install:** with LocalDevVPN connected, open SideStore → My Apps → **+** → iCloud Drive → `StickyNotes.ipa`, with the branch and sha it was built from and its expected size (about 7 MB lately; give the real figure), so he can see the new copy has finished syncing → "Register App ID for each extension".
   - **Check:** exactly which states to test on the phone, taken from the PR's **Not verified** list.

Never edit his data, and never ask for his Apple ID. If an install fails with an App ID limit (a free account gets 10 new IDs a week), say so and stop.
