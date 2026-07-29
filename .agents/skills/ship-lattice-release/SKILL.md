---
name: ship-lattice-release
description: Ship changes in the ejohane/lattice repository all the way from a ready pull request through a published, updater-ready macOS release. Use when the user asks to create or finish a Lattice PR and release, ship or publish the current Lattice work, merge and watch the release, or report the resulting Lattice version and release notes.
---

# Ship Lattice Release

Carry the current Lattice change through PR validation, squash merge, semantic release, artifact verification, and final version reporting. Continue until the release is usable or a blocker requires user action.

## Guardrails

- Work only in `ejohane/lattice`. Confirm the repository and current worktree before mutating Git or GitHub state.
- Preserve unrelated working-tree changes. Stage only the requested files.
- Never push directly to `main`. Repair failures through the PR workflow.
- Use a Conventional Commit PR title. The squash title determines the semantic version: `feat` is minor, `!` is major, and other accepted types are patch.
- Prefer a squash merge so the validated PR title becomes the release commit.
- Do not report success merely because CI or the Release workflow is green. Verify the published release and updater assets.
- Do not expose or copy signing, notarization, or Sparkle secrets. A missing or invalid repository secret is a user-action blocker.

## 1. Prepare and publish the PR

1. Inspect `git status`, the branch, remotes, base divergence, and the full diff. Confirm every staged path belongs to the requested change.
2. Fetch `origin/main`. If the current branch is stale or already merged, create a fresh `codex/` branch from current `origin/main` and preserve only the intended work.
3. Run `git diff --check` and `bun run verify`. Also run `bun run mac:bundle` when app startup, packaging, installation, updates, or release behavior changed. Use local release-style archive and checksum validation for updater or installer work when practical.
4. Fix every local failure before committing. Re-run the failing check and then the complete required gate.
5. Commit with a Conventional Commit message, push the branch, and open a non-draft PR against `main`. Include `Summary` and `Validation` sections in the body.
6. Read the created PR back from GitHub. Confirm its title, base, head, non-draft state, and URL.

## 2. Watch and repair PR checks

1. Watch all checks with `gh pr checks <number> --watch --interval 10` or equivalent structured GitHub queries.
2. On failure, inspect the failed job and logs with `gh run view <run-id> --log-failed`.
3. Classify the failure before acting:
   - For a code, test, build, packaging, or workflow defect, fix it on the PR branch, run the relevant check plus the complete required gate, commit, push, and watch again.
   - For a confirmed transient GitHub runner or network failure, rerun only the failed jobs and keep watching.
   - For missing permissions, unavailable credentials, or invalid repository secrets, exhaust safe read-only diagnosis and ask the user to repair the external configuration.
4. Continue until every required check succeeds and GitHub reports the PR `CLEAN` and `MERGEABLE`.

## 3. Merge and capture the release commit

1. Reconfirm the PR is open, non-draft, clean, mergeable, and fully green.
2. Squash-merge it with `gh pr merge <number> --squash`.
3. Read the PR back and require `state: MERGED`.
4. Save the exact `mergeCommit.oid` as the release commit. Do not infer it from the local branch.

## 4. Watch and repair the release

1. Find the `Release` workflow run on `main` whose `headSha` exactly matches the release commit. Ignore older, newer, manual, or unrelated runs.
2. Watch that run through `Verify`, `Plan release`, both macOS architecture builds, appcast generation, and `Semantic release`.
3. If it fails, inspect the failed logs.
   - Rerun confirmed transient failures.
   - For a repository defect, create a follow-up repair PR with an appropriate Conventional Commit title, repeat the complete PR workflow, squash-merge it, replace the tracked release commit with that repair PR merge SHA, and watch the new `Release` run. Semantic release should then include all unreleased commits since the prior tag.
   - Treat signing, notarization, GitHub permission, and Sparkle secret failures as external blockers when they cannot be corrected in repository code.
4. Continue until the exact release run succeeds.

## 5. Verify the published build

1. Fetch tags and identify the `v*` tag whose peeled commit is the tracked release commit. Do not assume `releases/latest` belongs to this work.
2. Read that exact release with `gh release view <tag> --json tagName,name,publishedAt,url,body,isDraft,isPrerelease,assets`.
3. Require a published, non-draft, non-prerelease release and all six assets:
   - `lattice-macos-app-darwin-arm64.zip`
   - `lattice-macos-app-darwin-arm64.zip.sha256`
   - `lattice-macos-app-darwin-x64.zip`
   - `lattice-macos-app-darwin-x64.zip.sha256`
   - `lattice-macos-appcast-darwin-arm64.xml`
   - `lattice-macos-appcast-darwin-x64.xml`
4. Run `python3 .agents/skills/ship-lattice-release/scripts/verify_release.py <tag> --commit <release-commit>`. This verifies the exact tag and GitHub release, all six assets, the `sparkle:shortVersionString` XML elements, enclosure archive names, and the live `releases/latest` feeds when this is still the newest release.
5. Treat the verifier's JSON as the source for the final version, release URL, and notes. If publication is briefly eventually consistent, poll rather than declaring failure. If assets or appcast content remain wrong, follow the release repair loop.

## 6. Report the outcome

Respond only after the published-build checks pass. Lead with:

- the released version number without ambiguity,
- the release notes from the exact GitHub release body,
- the release URL.

Also mention the merged PR and that PR CI, release automation, architecture archives, checksums, and Sparkle appcasts were verified. Distinguish any unverified installation or live in-app update from release publication; do not imply the app was installed or updated unless that was separately tested.
