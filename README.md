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
  AGENTS.md
  config.json
```

`raw/` is immutable source material. `queue/` is operational state for external
agents. `wiki/` is agent-owned; the CLI initializes it but does not synthesize
or edit wiki pages. `skills/` contains plain markdown operating procedures that
any external harness can read. The root `AGENTS.md` is the default entrypoint
for agents that automatically look for repository or workspace instructions.

## Skills

Lattice skills are ordinary markdown files, not tool-specific plugin packages.
They describe reusable agent capabilities for maintaining a vault:

- `AGENTS.md`: root entrypoint for agent harnesses; points to the vault skills.
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

Install the latest released macOS app:

```bash
curl -fsSL https://raw.githubusercontent.com/ejohane/lattice/main/scripts/install-mac-app.sh | sh
```

The macOS app installer downloads the matching `Lattice.app` release zip for
your Mac architecture, verifies the `.sha256` checksum when `shasum` is
available, and installs it to `~/Applications/Lattice.app` by default. Released
apps include Sparkle update support, so subsequent releases can be installed
from the `Check for Updates...` menu item.

Build a development macOS app with Sparkle updates enabled:

```bash
swift build --package-path macos/LatticeCapture -c release
macos/LatticeCapture/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-dev

LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml \
LATTICE_SPARKLE_PUBLIC_ED_KEY="<public key from generate_keys>" \
LATTICE_APP_BUILD=1 \
bash scripts/build-mac-app.sh
```

Sparkle is only configured when `LATTICE_SPARKLE_FEED_URL` is present at build
time. These unsigned development builds add a `Check for Updates...` menu item
and enable Sparkle's automatic checks and automatic update installation. They
are not the official user distribution channel.

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

Give the vault a human-readable name:

```bash
bun run src/cli.ts --vault ./LatticeVault init --name "Research Vault"
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
lattice --vault ./LatticeVault init --name "Research Vault"
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

Install the Raycast adapter:

```bash
lattice --vault ./LatticeVault apps install raycast
```

On macOS, this downloads the compiled Raycast extension release artifact,
verifies its `.sha256` checksum, installs a managed copy under
`~/Library/Application Support/Lattice/apps/raycast/`, copies the compiled
extension into Raycast's local extension directory, and writes shared Lattice
app config with the vault path and CLI path. It does not run `bun install` or
build the extension on the user's machine.

Check the Raycast adapter:

```bash
lattice apps doctor raycast
```

## Binary Artifacts and Releases

GitHub Actions includes two workflows:

- `CI`: runs tests, typecheck, builds a local binary, smoke-tests
  `./dist/lattice --help`, and packages the compiled Raycast extension on
  pushes to `main` and pull requests.
- `Conventional PR Title`: requires every PR title to use Conventional Commit
  format so squash merges can drive semantic versioning.
- `Release`: on pushes to `main`, runs tests/typecheck, plans the next
  semantic-release version, builds packaged binary archives, packages the
  compiled Raycast extension, generates a signed Sparkle appcast for the macOS
  app, and runs semantic-release to tag and publish GitHub releases.

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
- `lattice-macos-app-darwin-arm64.zip` on the native `macos-15` arm64 runner.
- `lattice-macos-app-darwin-x64.zip` on the native `macos-15-intel` runner.
- `lattice-macos-appcast-darwin-arm64.xml` on the native `macos-15` arm64 runner.
- `lattice-macos-appcast-darwin-x64.xml` on the native `macos-15` arm64 runner.
- `lattice-raycast-extension-compiled.tar.gz` on `ubuntu-latest`.

Each archive contains `lattice`, `README.md`, and `LICENSE`, plus a matching
`.sha256` checksum file, except the Raycast archive, which contains the compiled
extension bundle, `README.md`, and `LICENSE`, and the macOS app zips, which
contain `Lattice.app`. The CLI archives also include `scripts/install.sh` for
auditability. The curl installers, `lattice update`,
`lattice apps install raycast`, and the macOS app's Sparkle updater consume
these release assets from the latest GitHub release.

Mac app update publishing requires Sparkle EdDSA keys in GitHub Actions:

- `LATTICE_SPARKLE_PUBLIC_ED_KEY`: the public key embedded in released
  `Lattice.app` bundles.
- `LATTICE_SPARKLE_PRIVATE_ED_KEY`: the exported private key used only in CI to
  sign `lattice-macos-appcast.xml`.

Generate and export the release key on a trusted Mac:

```bash
swift build --package-path macos/LatticeCapture -c release
macos/LatticeCapture/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-release
macos/LatticeCapture/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-release -p
macos/LatticeCapture/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-release -x sparkle-private-key.txt
```

Set `LATTICE_SPARKLE_PUBLIC_ED_KEY` to the `-p` output and
`LATTICE_SPARKLE_PRIVATE_ED_KEY` to the contents of `sparkle-private-key.txt`.

Install a downloaded archive manually:

```bash
tar -xzf lattice-darwin-arm64.tar.gz
install -m 0755 lattice-darwin-arm64/lattice ~/.local/bin/lattice
unzip lattice-macos-app-darwin-arm64.zip
mv Lattice.app ~/Applications/
```

The macOS app bundles are ad-hoc signed so Sparkle can validate update archives,
but they are not Developer ID signed or notarized. They are intended for local
developer distribution today; a future signed/notarized release would need Apple
Developer credentials and a separate signing step. Set `LATTICE_CODESIGN_IDENTITY`
when building if you want `scripts/build-mac-app.sh` to use a real signing
identity instead of the default ad-hoc signature.

### Development Mac App Updates

Use Sparkle's development appcast loop to test in-app updates before official
signing and notarization exist:

```bash
# Terminal 1: serve the development update directory.
mkdir -p dist/sparkle-dev
cd dist/sparkle-dev
python3 -m http.server 8000
```

```bash
# Terminal 2: create a newer update archive and appcast.
LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml \
LATTICE_SPARKLE_DOWNLOAD_URL_PREFIX=http://localhost:8000 \
LATTICE_SPARKLE_ACCOUNT=lattice-dev \
LATTICE_APP_BUILD=2 \
bun run package:mac-dev-update
```

Install or launch the older build first, then use `Check for Updates...` from
the Lattice menu bar menu. Sparkle compares `CFBundleVersion`, so increment
`LATTICE_APP_BUILD` for each development update.

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

## macOS App

The native macOS app lives in `macos/LatticeCapture/`. It opens a minimal
live-rendered Markdown editor with a quiet writing surface, lightweight
formatting toolbar, character count, menu bar controls, and a configurable
global hotkey. The editor autosaves the active note into one capture: the first
autosave creates the capture, subsequent edits update that same capture, and
the New Note toolbar action starts a fresh capture.

Draft text is persisted automatically under Application Support as you type.
When the editor loses focus, is hidden, is closed, or the app quits, a non-empty
draft is committed to the active vault as a `macos-app` capture and then cleared
after the capture succeeds. If the commit fails, the draft stays on disk for the
next launch.

Build and run the app from source:

```bash
bun run mac:build
bun run mac:run
```

Build a local `.app` bundle:

```bash
bun run mac:bundle
open "dist/Lattice.app"
```

## Raycast Extension

The extension lives in `raycast-extension/` and remains a thin adapter over the
installed CLI. It shells out to the configured `lattice` binary with
`LATTICE_VAULT_PATH`; protocol logic stays in `src/cli.ts` and the SDK modules.

The preferred install path is:

```bash
lattice --vault ./LatticeVault apps install raycast
```

The installer consumes the compiled release artifact and avoids install-time
dependency downloads. To build from source while developing the extension:

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

- `Lattice Path`: optional override for the `lattice` binary path.
- `Vault Path`: optional override for the local vault. Defaults to the vault
  configured by `lattice apps install raycast`.

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
bun run mac:build
cd raycast-extension && bun run typecheck && bun run build
```
