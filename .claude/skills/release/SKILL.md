---
name: release
description: Publish develop as a new version of the addon, with its tag, zip and GitHub Release.
disable-model-invocation: true
---

# Release

A release starts on `develop`, up to date with `origin/develop`, on a clean working tree. When `release/<version>` already has an open PR to `main` (a release that stopped), take its version and start at step 3.

Boris decides twice: the version (step 1), and shipping it (step 4), whose yes covers the merge into `main`, the tag, the GitHub Release and the merge back into `develop` of steps 5 and 6.

When a command exits non-zero, stop there and report its message: the scripts name what failed.

1. **Propose the version.** List the commit subjects since the last tag, `git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo origin/main)..origin/develop`. Any `feat` bumps the minor, otherwise the patch; the major stays 0 until Boris says otherwise. Ask Boris through `AskUserQuestion` to confirm it or give another; his answer is the version. Done when he has picked one.

2. **Cut the release.** `git switch -c release/<version>`, `npm version <version> --no-git-tag-version`, `npm test`, commit `package.json` and `package-lock.json` as `chore(release): <version>`, `git push -u origin release/<version>`, then `gh pr create --base main` titled `chore(release): <version>`, its body listing the PRs since the last tag. Done when it prints the PR's URL.

3. **Wait for CI.** Run `gh pr checks <url>` until it lists checks, since the workflows register a few seconds after the PR opens, then `gh pr checks <url> --watch`. Done when every check passes; a failing check ends the skill with its name.

4. **Show the changes.** Print the commit subjects of `origin/main..release/<version>`, then ask Boris through `AskUserQuestion` whether to ship it. A no ends the skill, leaving the PR open.

5. **Merge.** `gh pr merge <url> --merge`: a merge commit, so that the tag on `main` stays reachable from `develop` and the next version's log starts at the right commit. Done when the PR shows as merged.

6. **Finish.**
   - `git switch main`, `git pull --ff-only`, `npm run release`: tests, `dist/VepIndustriesMarket-<version>.zip`, the annotated tag `v<version>`, and a copy into the game's AddOns folder.
   - `git push origin v<version>`, then `gh release create v<version> dist/VepIndustriesMarket-<version>.zip --title "VepIndustries Market <version>" --generate-notes`.
   - `git switch develop`, `git pull --ff-only`, `git merge --no-ff main -m "chore(release): merge v<version> back into develop"`, `git push`.

   Done when the GitHub Release lists the zip and `origin/develop` contains `v<version>`.

7. **Report** the tag, the GitHub Release's URL and the zip's path, which Boris sends to his friends himself (`README.md`, « Diffusion »).
