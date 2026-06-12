#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifact="${LATTICE_RAYCAST_ARTIFACT:-lattice-raycast-extension-compiled}"
out_dir="${LATTICE_ARTIFACT_DIR:-dist}"
work_dir="$out_dir/$artifact"
extension_dir="$work_dir/raycast-extension"

rm -rf "$work_dir"
mkdir -p "$extension_dir"

(
  cd raycast-extension
  bun run ray build \
    --environment dist \
    --output "$repo_root/$extension_dir" \
    --non-interactive
)

mkdir -p "$extension_dir/assets"
cp assets/icon.svg "$extension_dir/assets/icon.svg"
rm -rf "$extension_dir/assets/icon-options"

bun -e '
const fs = require("node:fs");
const manifestPath = process.argv[1];
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.icon = "assets/icon.svg";
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
' "$extension_dir/package.json"

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
