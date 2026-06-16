#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact="${LATTICE_MAC_APP_ARTIFACT:-}"
out_dir="${LATTICE_ARTIFACT_DIR:-$repo_root}"

if [[ -z "$artifact" ]]; then
  arch="$(uname -m)"
  case "$arch" in
    arm64|aarch64) artifact="lattice-macos-app-darwin-arm64" ;;
    x86_64|amd64) artifact="lattice-macos-app-darwin-x64" ;;
    *)
      printf 'Unsupported macOS architecture: %s\n' "$arch" >&2
      exit 1
      ;;
  esac
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'The macOS app can only be packaged on macOS.\n' >&2
  exit 1
fi

app_path="$("$repo_root/scripts/build-mac-app.sh" | tail -n 1)"
archive="$out_dir/$artifact.zip"
checksum="$archive.sha256"

mkdir -p "$out_dir"
rm -f "$archive" "$checksum"

ditto -c -k --keepParent "$app_path" "$archive"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$archive" > "$checksum"
else
  printf 'warning: shasum not found; skipping checksum\n' >&2
fi

printf '%s\n' "$archive"
