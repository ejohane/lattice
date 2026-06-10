# Lattice

Local-first context capture protocol for agent-maintained personal wikis.

The product loop is:

```text
Raycast, CLI, or another thin capture surface
-> lattice CLI
-> immutable raw capture files and screenshots
-> pending queue
-> external agent maintains wiki pages
-> agent marks captures ingested
```

Lattice owns capture and raw source preparation. Codex, Claude Code, GitHub
Copilot, OpenCode, or another external harness owns wiki maintenance using the
skills stored in the vault.

## What It Does

- Captures quick notes from Raycast or the CLI.
- Saves raw captures as stable JSON records under `raw/captures/`.
- Captures timestamp, local date, source, active app/window, screenshots, and
  metadata errors.
- Appends capture records to `raw/log.jsonl`.
- Adds operational queue entries to `queue/pending.jsonl`.
- Initializes a wiki workspace and agent skills without maintaining the
  wiki itself.
- Marks captures ingested after an external agent has incorporated them.
- Exports pending source material into portable packs when needed.

## Vault Layout

```text
LatticeVault/
  raw/
    captures/YYYY-MM-DD/cap_...json
    screenshots/YYYY-MM-DD/cap_....png
    log.jsonl
  queue/
    pending.jsonl
    ingested.jsonl
  wiki/
    index.md
    log.md
    pages/
  skills/
    AGENTS.md
    ingest-captures.md
    maintain-wiki.md
    answer-from-wiki.md
    lint-wiki.md
  exports/packs/
  config.json
```

`raw/` is immutable source material. `queue/` is operational state for external
agents. `wiki/` is agent-owned; the CLI initializes it but does not synthesize
or edit wiki pages. `skills/` contains plain markdown operating procedures that
any external harness can read.

## Skills

Lattice skills are ordinary markdown files, not tool-specific plugin packages.
They describe reusable agent capabilities for maintaining a vault:

- `skills/AGENTS.md`: entry point and shared agent contract.
- `skills/ingest-captures.md`: consume pending captures and update the wiki.
- `skills/maintain-wiki.md`: reorganize pages, links, citations, and stale
  claims.
- `skills/answer-from-wiki.md`: answer from durable wiki knowledge without
  overclaiming.
- `skills/lint-wiki.md`: health-check citations, links, orphans, and
  contradictions.

`lattice init` installs the bundled skills into the vault without overwriting
existing skill files. You can install or update them explicitly:

```bash
bun run src/cli.ts --vault ./LatticeVault skills install
bun run src/cli.ts --vault ./LatticeVault skills install --force
```

## CLI

Install dependencies:

```bash
bun install
```

Install the latest released binary in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/ejohane/lattice/main/scripts/install.sh | sh
```

The installer detects macOS arm64, macOS x64, or Linux x64, downloads the
matching GitHub release archive, verifies its `.sha256` checksum when `shasum`
or `sha256sum` is available, and installs `lattice` to `~/.local/bin`.

Install a specific release or destination:

```bash
curl -fsSL https://raw.githubusercontent.com/ejohane/lattice/main/scripts/install.sh | LATTICE_VERSION=v0.1.0 LATTICE_INSTALL_DIR=/usr/local/bin sh
```

Build a standalone CLI binary for the current platform:

```bash
bun run build
./dist/lattice --help
```

Install the current-platform binary locally as `lattice`:

```bash
bun run install:local
lattice --vault ./LatticeVault init
```

`install:local` copies the compiled binary to `~/.local/bin/lattice` by
default. Override the destination when needed:

```bash
LATTICE_INSTALL_DIR=/usr/local/bin bun run install:local
```

Build explicit macOS artifacts with Bun's executable targets:

```bash
bun run build:binary:darwin-arm64
bun run build:binary:darwin-x64
bun run build:binary:linux-x64
```

Those commands write `dist/lattice-darwin-arm64`, `dist/lattice-darwin-x64`,
and `dist/lattice-linux-x64`. You can also pass any Bun executable target
directly:

```bash
LATTICE_TARGET=bun-linux-x64 bun run build:binary
```

Initialize a vault:

```bash
bun run src/cli.ts --vault ./LatticeVault init
```

Capture a note:

```bash
bun run src/cli.ts --vault ./LatticeVault capture --body "Need to revisit the capture flow."
```

Capture without a screenshot:

```bash
bun run src/cli.ts --vault ./LatticeVault capture --body "Fast note." --no-screenshot
```

Read from stdin:

```bash
echo "Follow up on agent ingestion workflow." | bun run src/cli.ts --vault ./LatticeVault capture --stdin
```

List pending captures:

```bash
bun run src/cli.ts --vault ./LatticeVault pending
```

Mark captures ingested after an agent updates the wiki:

```bash
bun run src/cli.ts --vault ./LatticeVault mark-ingested cap_2026-06-09T10-00-00_abcd1234 --agent codex
```

Check vault health:

```bash
bun run src/cli.ts --vault ./LatticeVault doctor
```

Create a portable pack of pending captures and skills:

```bash
bun run src/cli.ts --vault ./LatticeVault pack
```

All operational commands support `--json` where machine-readable output is
useful for adapters.

After local install, the same commands are available through the binary:

```bash
lattice --vault ./LatticeVault capture --body "Need to revisit the capture flow."
lattice --vault ./LatticeVault pending
```

Update an installed binary in place:

```bash
lattice update
```

Install a specific release:

```bash
lattice update --version v0.1.0
```

`lattice update` downloads the matching release archive for the current platform,
verifies the `.sha256` checksum, and replaces the running binary atomically. When
running from source with `bun run src/cli.ts`, pass an explicit destination so it
does not try to replace the Bun runtime:

```bash
bun run src/cli.ts update --install-dir ~/.local/bin
```

## Binary Artifacts and Releases

GitHub Actions includes two workflows:

- `CI`: runs tests, typecheck, builds a local binary, and smoke-tests
  `./dist/lattice --help` on pushes to `main` and pull requests.
- `Conventional PR Title`: requires every PR title to use Conventional Commit
  format so squash merges can drive semantic versioning.
- `Release`: on pushes to `main`, runs tests/typecheck, builds packaged binary
  archives, and runs semantic-release to tag and publish GitHub releases.

Use squash merges with Conventional Commit PR titles:

```text
feat: add capture search
fix(cli): handle missing vault config
feat!: change vault protocol layout
```

semantic-release analyzes commits on `main` and creates `vX.Y.Z` tags:

- `feat` creates a minor release.
- `!` after the type or scope creates a major release.
- All other accepted types create a patch release so every merge to `main`
  produces release assets that `lattice update` can install.

The release workflow currently builds:

- `lattice-darwin-arm64.tar.gz` on the native `macos-15` arm64 runner.
- `lattice-darwin-x64.tar.gz` on the native `macos-15-intel` runner.
- `lattice-linux-x64.tar.gz` on `ubuntu-latest`.

Each archive contains `lattice`, `README.md`, and `LICENSE`, plus a matching
`.sha256` checksum file. It also includes `scripts/install.sh` for auditability.
Release publishing uses the standard `GITHUB_TOKEN`; no additional secrets are
required. The curl installer and `lattice update` both consume these release
assets from the latest GitHub release.

Install a downloaded archive manually:

```bash
tar -xzf lattice-darwin-arm64.tar.gz
install -m 0755 lattice-darwin-arm64/lattice ~/.local/bin/lattice
```

The macOS binaries are unsigned and not notarized. They are intended for local
developer distribution today; a future signed/notarized release would need Apple
Developer credentials and a separate signing step.

## Capture Record

Raw capture JSON is stable and agent-friendly:

```json
{
  "schema_version": 1,
  "kind": "capture",
  "id": "cap_2026-06-09T10-00-00_abcd1234",
  "created_at": "2026-06-09T15:00:00.000Z",
  "local_date": "2026-06-09",
  "body": "Need to revisit the capture flow.",
  "source": "cli",
  "context": {
    "active_app": "Code",
    "active_window": "lattice",
    "screenshot_path": "raw/screenshots/2026-06-09/cap_2026-06-09T10-00-00_abcd1234.png",
    "metadata_errors": []
  }
}
```

Pending queue entries reference raw files instead of duplicating capture bodies.

## Raycast Extension

The extension lives in `raycast-extension/` and remains a thin adapter over the
CLI. It shells out to the configured project with `LATTICE_VAULT_PATH`; protocol
logic stays in `src/cli.ts` and the SDK modules.

Install and build:

```bash
cd raycast-extension
bun install
bun run build
```

Commands:

- `Capture Thought`
- `Pending Captures`
- `Mark Ingested`
- `Run Doctor`
- `Create Pack`
- `Install Skills`
- `Open Lattice Vault`
- `Open Queue`
- `Open Raw Captures`
- `Open Screenshots`
- `Open Wiki`
- `Open Agent Skills`
- `Open Packs`

Preferences:

- `Project Path`: absolute path to this project folder.
- `Vault Path`: absolute path to the local vault.
- `Bun Path`: usually `bun`; the adapter resolves common Bun install paths when
  Raycast's runtime PATH is sparse.

When saving from Raycast, the extension closes the Raycast window before calling
the CLI so the screenshot and active app/window metadata refer to the workspace
you were using, not the Raycast form.

Folder-opening commands call `lattice init` through the configured CLI before
opening paths. CLI operation commands call `capture`, `pending`,
`mark-ingested`, `doctor`, `pack`, and `skills install` directly.

## Verification

Run automated checks:

```bash
bun test
bun run typecheck
cd raycast-extension && bun run typecheck && bun run build
```
