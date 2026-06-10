#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifact="${LATTICE_RAYCAST_ARTIFACT:-lattice-raycast-extension}"
out_dir="${LATTICE_ARTIFACT_DIR:-dist}"
work_dir="$out_dir/$artifact"

rm -rf "$work_dir"
mkdir -p "$work_dir/assets"

mkdir -p "$work_dir/raycast-extension"
tar \
  --exclude node_modules \
  --exclude .raycast \
  --exclude dist \
  --exclude './assets/icon-options' \
  --exclude 'assets/icon-options' \
  --exclude './raycast-env.d.ts' \
  --exclude 'raycast-env.d.ts' \
  --exclude './com.*.raycast-dev.plist' \
  --exclude 'com.*.raycast-dev.plist' \
  -cf - -C raycast-extension . | tar -xf - -C "$work_dir/raycast-extension"

cp assets/icon.svg "$work_dir/assets/icon.svg"
cp README.md LICENSE "$work_dir/"

mkdir -p "$out_dir"
tar -czf "$out_dir/$artifact.tar.gz" -C "$work_dir" .

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$out_dir/$artifact.tar.gz" > "$out_dir/$artifact.tar.gz.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$out_dir/$artifact.tar.gz" > "$out_dir/$artifact.tar.gz.sha256"
else
  printf 'warning: shasum or sha256sum not found; skipping checksum\n' >&2
fi

printf '%s\n' "$out_dir/$artifact.tar.gz"
