# Lattice

Lattice for macOS is a deliberately focused editor for portable Markdown files.

Choose a folder and Lattice recursively lists its visible `.md` files in a
single left sidebar. Select a file to edit its Markdown body in the live editor
on the right. Headings, emphasis, inline code, bullets, and task lists receive
native presentation while the underlying file remains ordinary Markdown.
Lattice-owned YAML frontmatter is hidden and preserved unchanged when the body
autosaves directly to that file. Other YAML frontmatter remains visible.

Use the New Note button in the trailing toolbar to create an empty Markdown
file. New files start with an available `Untitled.md` name and are renamed once
from their first meaningful line when that line ends or the note is left.
Later edits do not keep changing the filename.

The live editor reveals Markdown syntax only for the active construct and
collapses it as soon as the caret moves beyond that construct. New notes turn
their first typed line into a real Markdown H1.
List returns continue the current bullet or task, empty items exit the list,
and rendered task checkboxes toggle the source between `[ ]` and `[x]`.

The current macOS app still excludes links, attachments, tables, autocomplete,
task sync, modes, themes, and other note-specific features. Those capabilities
may return individually after the core editing loop is proven fast and dependable.

The existing iPhone and iPad app remains in the repository while the macOS app
is rebuilt from this smaller foundation.

## Install

Install the latest released macOS app:

```bash
curl -fsSL https://raw.githubusercontent.com/ejohane/lattice/main/scripts/install-mac-app.sh | sh
```

The installer downloads the matching `Lattice.app` release zip for your Mac
architecture, verifies the `.sha256` checksum when `shasum` is available, and
installs the app to `~/Applications` by default.

Override the destination or version with environment variables:

```bash
LATTICE_VERSION=v1.7.0 LATTICE_APP_INSTALL_DIR=/Applications \
  curl -fsSL https://raw.githubusercontent.com/ejohane/lattice/main/scripts/install-mac-app.sh | sh
```

## Develop

Build and run the macOS app from source:

```bash
bun run mac:build
bun run mac:run
```

Build, install, and run the iPhone or iPad app in Simulator:

```bash
bun run ios:run
bun run ios:run:ipad
```

Use another installed simulator by name:

```bash
SIMULATOR_NAME="iPhone Air" bun run ios:run
```

Build the iOS app for Simulator without launching it:

```bash
bun run ios:build
bun run ios:build:ipad
```

Create a local iOS archive when signing is configured in Xcode:

```bash
bun run ios:archive
```

Run shared Swift tests:

```bash
bun run mac:test
```

Build a local `.app` bundle:

```bash
bun run mac:bundle
open "dist/Lattice.app"
```

Run the standard verification command:

```bash
bun run verify
```

See [docs/mac-markdown-editor.md](docs/mac-markdown-editor.md) for the intentionally
small macOS editor contract.

## Sparkle Updates

Build a development macOS app with Sparkle updates enabled:

```bash
swift build --package-path apps/lattice -c release
apps/lattice/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-dev

LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml \
LATTICE_SPARKLE_PUBLIC_ED_KEY="$(apps/lattice/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-dev -p)" \
LATTICE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
bash scripts/build-mac-app.sh
```

Sparkle is configured only when `LATTICE_SPARKLE_FEED_URL` is present at build
time. Updater-enabled builds also require stable code signing. Do not ship
ad-hoc signed updater archives: macOS ties Reminders permission to the app's
code requirement, and ad-hoc signatures change on every update.

Generate a local development update archive and appcast:

```bash
LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml \
LATTICE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
bun run package:mac-dev-update
```

For disposable local Sparkle plumbing tests only, you can opt into ad-hoc
signing with `LATTICE_ALLOW_ADHOC_UPDATE_SIGNATURE=1`. That mode can reset
Reminders permission after the update installs.

## Release

Release automation uses Conventional Commit titles on `main` through
semantic-release.

Release artifacts:

- `lattice-macos-app-darwin-arm64.zip`
- `lattice-macos-app-darwin-arm64.zip.sha256`
- `lattice-macos-app-darwin-x64.zip`
- `lattice-macos-app-darwin-x64.zip.sha256`
- `lattice-macos-appcast-darwin-arm64.xml`
- `lattice-macos-appcast-darwin-x64.xml`

Mac app update publishing requires Sparkle EdDSA keys in GitHub Actions:

- `LATTICE_SPARKLE_PUBLIC_ED_KEY`: embedded in release app bundles.
- `LATTICE_SPARKLE_PRIVATE_ED_KEY`: used to sign appcasts.
- `LATTICE_CODESIGN_IDENTITY`: Developer ID Application identity name.
- `LATTICE_MACOS_CODESIGN_CERTIFICATE_BASE64`: base64-encoded `.p12` signing certificate.
- `LATTICE_MACOS_CODESIGN_CERTIFICATE_PASSWORD`: password for the `.p12` file.
- `LATTICE_MACOS_KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `LATTICE_NOTARY_KEY_ID`: App Store Connect API key identifier.
- `LATTICE_NOTARY_ISSUER_ID`: App Store Connect API issuer identifier.
- `LATTICE_NOTARY_PRIVATE_KEY`: contents of the matching `.p8` private key.

Release builds are submitted to Apple's notarization service after Developer ID
signing. The accepted ticket is stapled to `Lattice.app` before the final ZIP,
checksum, and Sparkle appcast are generated.
