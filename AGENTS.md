# Lattice Repository Agent Guide

Lattice is centered on the native Apple app project in `apps/Lattice`. The app writes
portable Markdown notes into a local notes folder.

## Scope

- Keep the macOS app, Markdown note storage, packaging, and release automation
  scoped to the requested workstream.
- Do not reintroduce CLI, Raycast, bundled skills, wiki, queue, JSON capture,
  screenshot, or context-metadata systems unless the task explicitly asks for
  that work.
- Preserve local-first behavior. Notes should remain ordinary Markdown files on
  disk.
- Keep Sparkle update changes app-native and release-artifact based.

## Verification

- Run `bun run verify` before handing off code changes. This covers Swift tests,
  the macOS app build, and the iOS Simulator build.
- Run `bun run mac:bundle` when changing app startup, packaging, installer, or
  update behavior.
- For updater or installer changes, test against a local release-style archive
  and checksum when possible.

## PR and MR Titles

Every PR/MR title must use Conventional Commit format because release automation
uses the squash-merge title on `main` to decide semantic version bumps and tag
releases.

Use:

```text
feat(mac): add recent notes menu
fix(notes): handle deleted active note
docs: explain local install
ci: publish Sparkle appcast
feat!: change note folder layout
```

Release impact:

- `feat` creates a minor release.
- `!` after the type or scope creates a major release.
- All other accepted types create a patch release so every merge to `main`
  produces updateable app artifacts.

Prefer squash merges so the validated PR/MR title becomes the commit message on
`main`.
