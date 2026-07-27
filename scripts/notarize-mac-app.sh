#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${LATTICE_MAC_APP_ARCHIVE:-}"
notary_key_id="${LATTICE_NOTARY_KEY_ID:-}"
notary_issuer_id="${LATTICE_NOTARY_ISSUER_ID:-}"
notary_private_key_file="${LATTICE_NOTARY_PRIVATE_KEY_FILE:-}"

if [[ -z "$archive" ]]; then
  printf 'error: set LATTICE_MAC_APP_ARCHIVE to the packaged Lattice zip.\n' >&2
  exit 1
fi

if [[ "$archive" != /* ]]; then
  archive="$repo_root/$archive"
fi

if [[ ! -f "$archive" ]]; then
  printf 'error: macOS app archive not found: %s\n' "$archive" >&2
  exit 1
fi

if [[ -z "$notary_key_id" || -z "$notary_issuer_id" || -z "$notary_private_key_file" ]]; then
  cat >&2 <<'EOF'
error: notarization requires LATTICE_NOTARY_KEY_ID,
LATTICE_NOTARY_ISSUER_ID, and LATTICE_NOTARY_PRIVATE_KEY_FILE.
EOF
  exit 1
fi

if [[ ! -f "$notary_private_key_file" ]]; then
  printf 'error: notarization private key not found: %s\n' "$notary_private_key_file" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

xcrun notarytool submit "$archive" \
  --key "$notary_private_key_file" \
  --key-id "$notary_key_id" \
  --issuer "$notary_issuer_id" \
  --wait

ditto -x -k "$archive" "$tmp_dir"
app_path="$tmp_dir/Lattice.app"
if [[ ! -d "$app_path" ]]; then
  printf 'error: archive did not contain Lattice.app\n' >&2
  exit 1
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl -a -t execute -vv "$app_path"

rm -f "$archive" "$archive.sha256"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$app_path" "$archive"
archive_dir="$(dirname "$archive")"
archive_name="$(basename "$archive")"
(
  cd "$archive_dir"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

printf 'Notarized archive: %s\n' "$archive"
