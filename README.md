# Lattice

Minimal Mac-first capture and synthesis system.

The product loop is:

```text
Raycast quick capture
-> local vault folder
-> manual synthesis command
-> provider-backed JSON analysis
-> daily brief + proposed wiki updates
```

The Raycast extension is intentionally thin. The Bun/TypeScript CLI owns storage,
metadata capture, synthesis, validation, and rendering.

## What It Does

- Captures quick notes from Raycast or the CLI.
- Saves raw captures in an append-only local vault.
- Captures timestamp, active app/window, and screenshots by default on macOS.
- Runs manual one-pass synthesis for a selected date.
- Uses a small LLM harness boundary: Copilot SDK, OpenCode, OpenAI API, or mock.
- Parses and validates model JSON with Zod before writing outputs.
- Generates daily briefs automatically.
- Generates wiki update proposals for review instead of editing the wiki silently.

## Vault Layout

```text
LatticeVault/
  raw/                  # append-only JSONL by date
  captures/             # individual capture JSON files
  screenshots/          # screenshots grouped by date
  daily/                # generated daily briefs
  wiki/
    Inbox/              # starting point for curated pages
  index/                # compact page/taxonomy/alias indexes
  review/               # proposed wiki updates
  synthesis/
    runs/               # raw synthesis run artifacts
  config.json
```

Raw captures are source material. Daily notes are generated logs. Wiki updates
are review proposals.

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

Synthesize with the configured harness:

```bash
bun run src/cli.ts --vault ./LatticeVault synthesize --date 2026-06-09
```

Override the harness for one run:

```bash
bun run src/cli.ts --vault ./LatticeVault synthesize --date 2026-06-09 --harness opencode --model openai/gpt-5.4-mini
```

Synthesize without spending tokens:

```bash
bun run src/cli.ts --vault ./LatticeVault synthesize --date 2026-06-09 --provider mock
```

Check a provider:

```bash
bun run src/cli.ts provider-check --provider mock
```

## LLM Harnesses

The synthesis engine calls one narrow interface:

```text
generateText({ model, system, prompt, temperature }) -> assistant text
```

Harnesses:

- `copilot`: GitHub Copilot SDK. This is the default work path.
- `opencode`: OpenCode CLI. Use this for OpenAI subscription-backed local synthesis.
- `openai`: OpenAI Responses API. Requires `OPENAI_API_KEY`.
- `mock`: deterministic token-free provider for tests and local verification.

Default vault config:

```json
{
  "llm": {
    "provider": "copilot",
    "model": "gpt-5.4-mini",
    "temperature": 0
  },
  "capture": {
    "screenshots_default": true
  }
}
```

The exact Copilot model identifier can be changed in `LatticeVault/config.json`
or overridden with `--model`.

For local OpenCode synthesis, use:

```json
{
  "llm": {
    "provider": "opencode",
    "model": "openai/gpt-5.4-mini",
    "temperature": 0
  }
}
```

The OpenCode adapter resolves `OPENCODE_BIN` first, then
`~/.opencode/bin/opencode`, then `opencode` on PATH. This lets Raycast use the
same OpenCode subscription-backed setup as your terminal without requiring an
OpenAI API key.

## Raycast Extension

The extension lives in `raycast-extension/`.

Install and build:

```bash
cd raycast-extension
bun install
bun run build
```

Commands:

- `Capture Thought`
- `Synthesize Captures`
- `Open Vault`
- `Open Daily Briefs`
- `Open Wiki Proposals`

Preferences:

- `Project Path`: absolute path to this project folder.
- `Vault Path`: absolute path to the local vault.
- `Bun Path`: usually `bun`.

When saving from Raycast, the extension closes the Raycast window before calling
the CLI so the screenshot and active app/window metadata refer to the workspace
you were using, not the Raycast form.

## Verification

Run automated checks:

```bash
bun test
bun run typecheck
cd raycast-extension && bun run typecheck && bun run build
```

Run token-free end-to-end verification:

```bash
bun run src/cli.ts verify
```
