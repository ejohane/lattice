# Lattice

Lattice is a universal Apple app for quickly writing Markdown notes into a
portable folder. The same SwiftUI app shell runs on macOS, iPhone, and iPad,
with native text views under the editor for platform editing behavior.

The app keeps one active note open per device. The first autosave creates a
Markdown file, later autosaves update that same file, and New Note starts a
fresh file.

## Notes Folder

On first run, Lattice asks you to choose a notes folder. The recommended folder
is an iCloud Drive-style `Lattice` folder when iCloud Drive is available, but any
user-controlled folder can be selected.

Lattice stores notes as:

```text
~/Documents/Lattice/
  notes/
    2026-06-17/
      2026-06-17T14-32-10.md
```

Notes are ordinary `.md` files with no JSON wrapper, database, front matter, or
app-specific sidecar index.

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

The mac editor intentionally live-renders Markdown while keeping notes as plain
`.md` files. See [docs/mac-markdown-editor.md](docs/mac-markdown-editor.md)
before changing editor rendering or keyboard behavior.

## Sparkle Updates

Build a development macOS app with Sparkle updates enabled:

```bash
swift build --package-path apps/lattice -c release
apps/lattice/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-dev

LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml \
LATTICE_SPARKLE_PUBLIC_ED_KEY="$(apps/lattice/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lattice-dev -p)" \
bash scripts/build-mac-app.sh
```

Sparkle is configured only when `LATTICE_SPARKLE_FEED_URL` is present at build
time. Release builds also require `LATTICE_SPARKLE_PUBLIC_ED_KEY`.

Generate a local development update archive and appcast:

```bash
LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml \
bun run package:mac-dev-update
```

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
