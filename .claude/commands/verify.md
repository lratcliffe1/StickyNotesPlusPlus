# Verify a change

Use before calling any branch done. Xcode isn't installed here, so CI is the build machine and the screenshots are your eyes. Your own "it works" is never the last word.

1. **Push, then wait for both workflows** on the branch's latest commit: `gh run list --branch <branch> --limit 4`, then `gh run watch <id> --exit-status` for **iOS Quality** (build + unit tests) and **Screenshots**. If one is red, read `gh run view <id> --log-failed` and fix the cause. Don't retry blindly.
2. **Look at the screenshots.** `gh run download <id> -n screenshots -D <scratch dir>`, shrink them (`sips -Z 900 *.png`), then open and **look at** each changed state in colour **and** greyscale. Check what the plan said should be visible, and that nothing else moved. If the change has a state the harness can't reach, add a scenario to `UITestHarness` and a row to `scripts/screenshots.sh` first.
3. **Get a blind review.** Dispatch the `checker` agent with the plan's acceptance checks and the diff ref, not your summary. Fix the findings, and re-run steps 1–2 after any fix.
4. **Update the PR body** with:
   - **Verified:** what CI proved (tests by name for new logic), what you saw in which screenshot.
   - **Not verified:** anything only the phone can show (widget, touch behaviour, the real store), plus anything the review left unverified.
5. **Hand over to Liam:** build an installable copy (`/ship`) and tell him exactly what to check on his phone.
