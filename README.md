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
