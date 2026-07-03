# Lattice Repository Agent Guide

Lattice is centered on the universal Apple app in `apps/lattice`. The app writes
portable Markdown notes into a user-selected notes folder and shares app logic
across macOS, iPhone, and iPad.

## Scope

- Keep the universal Apple app, Markdown note storage, packaging, and release automation
  scoped to the requested workstream.
- Do not reintroduce CLI, Raycast, bundled skills, wiki, queue, JSON capture,
  screenshot, or context-metadata systems unless the task explicitly asks for
  that work.
- Preserve local-first behavior. Notes should remain ordinary Markdown files on
  disk.
- Keep Sparkle update changes macOS-native and release-artifact based.

## Verification

- Run `bun run verify` before handing off code changes.
- Run `bun run mac:bundle` when changing macOS app startup, packaging,
  installer, or update behavior.
- For updater or installer changes, test against a local release-style archive
  and checksum when possible.

## Installing on Erik's iPhone

Use this flow when asked to put a fresh iOS build on the physical device. The
repo's `ios:run` scripts target Simulator only, so physical-device installs use
the Xcode project and `devicectl` directly.

1. Sync the checkout to the requested base, usually latest `origin/main`.

   ```sh
   git fetch origin main
   git switch --detach origin/main
   ```

2. Confirm the phone is available.

   ```sh
   xcrun devicectl list devices --search "Erik" --json-output -
   ```

   Known identifiers:

   - CoreDevice identifier: `54401304-511F-55CB-B87B-6CD55B950056`
   - Hardware UDID / Xcode destination id: `00008140-001A686E0EDB001C`

3. Build for the physical device with local automatic signing overrides.

   ```sh
   xcodebuild \
     -project apps/lattice/iOS/Lattice.xcodeproj \
     -scheme Lattice \
     -destination 'platform=iOS,id=00008140-001A686E0EDB001C' \
     -derivedDataPath .build/ios-device-derived-data \
     -clonedSourcePackagesDirPath .build/ios-device-source-packages \
     CODE_SIGN_STYLE=Automatic \
     DEVELOPMENT_TEAM=TRA7965NM5 \
     CODE_SIGN_IDENTITY='Apple Development' \
     build
   ```

   The matching local provisioning profile is Xcode-managed
   (`iOS Team Provisioning Profile: com.ejohane.lattice.ios`), so forcing
   manual signing can fail even when the profile exists.

4. Install and launch the built app.

   ```sh
   xcrun devicectl device install app \
     --device 54401304-511F-55CB-B87B-6CD55B950056 \
     .build/ios-device-derived-data/Build/Products/Debug-iphoneos/Lattice.app

   xcrun devicectl device process launch \
     --device 54401304-511F-55CB-B87B-6CD55B950056 \
     com.ejohane.lattice.ios
   ```

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
