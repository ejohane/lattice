# Lattice Repository Agent Guide

This file is for agents working on the Lattice source repository. It is not the
same as `skills/AGENTS.md`, which is copied into user vaults by the CLI.

## Scope

- Keep protocol, vault, Raycast, packaging, and release changes scoped to the
  requested workstream.
- Do not edit `skills/AGENTS.md` unless the task is specifically changing the
  vault skill instructions that Lattice installs for users.
- Preserve local-first behavior. Release automation should publish binaries, not
  add remote service dependencies to normal CLI operation.

## Verification

- Run `bun run verify` before handing off code changes.
- Run `bun run build:binary` when changing CLI startup, packaging, installer,
  update, or release behavior.
- For updater or installer changes, test against a local release-style archive
  and checksum when possible.

## PR and MR Titles

Every PR/MR title must use Conventional Commit format because release automation
uses the squash-merge title on `main` to decide semantic version bumps and tag
releases.

Use:

```text
feat: add capture search
fix(cli): handle missing vault config
perf(index): speed up wiki scan
docs: explain local install
ci: publish release binaries
feat!: change vault protocol layout
```

Release impact:

- `feat` creates a minor release.
- `!` after the type or scope creates a major release.
- All other accepted types create a patch release so every merge to `main`
  produces updateable binary artifacts.

Prefer squash merges so the validated PR/MR title becomes the commit message on
`main`.
