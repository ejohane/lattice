#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_path="$repo_root/apps/lattice"
sparkle_account="${LATTICE_SPARKLE_ACCOUNT:-lattice-dev}"
sparkle_feed_url="${LATTICE_SPARKLE_FEED_URL:-}"
sparkle_public_ed_key="${LATTICE_SPARKLE_PUBLIC_ED_KEY:-}"
sparkle_private_ed_key_file="${LATTICE_SPARKLE_PRIVATE_ED_KEY_FILE:-}"
download_url_prefix="${LATTICE_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
update_dir="${LATTICE_SPARKLE_UPDATE_DIR:-$repo_root/dist/sparkle-dev}"
artifact="${LATTICE_MAC_APP_ARTIFACT:-lattice-macos-app-dev}"
appcast_name="${LATTICE_SPARKLE_APPCAST_NAME:-appcast.xml}"
codesign_identity="${LATTICE_CODESIGN_IDENTITY:-}"
allow_adhoc_update_signature="${LATTICE_ALLOW_ADHOC_UPDATE_SIGNATURE:-0}"

if [[ -z "$sparkle_feed_url" ]]; then
  printf 'error: set LATTICE_SPARKLE_FEED_URL to the development appcast URL.\n' >&2
  printf 'example: LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml %s\n' "$0" >&2
  exit 1
fi

if [[ "$allow_adhoc_update_signature" != "1" && ( -z "$codesign_identity" || "$codesign_identity" == "-" ) ]]; then
  cat >&2 <<'EOF'
error: local updater archives need a stable LATTICE_CODESIGN_IDENTITY.

Ad-hoc signed updates are useful for Sparkle plumbing tests, but macOS will treat
each updated app as a different Reminders requester. Set
LATTICE_CODESIGN_IDENTITY, or set LATTICE_ALLOW_ADHOC_UPDATE_SIGNATURE=1 for a
disposable test that may reset Reminders permission.
EOF
  exit 1
fi

swift build --package-path "$package_path" -c release >/dev/null
sparkle_bin="$package_path/.build/artifacts/sparkle/Sparkle/bin"
generate_appcast="$sparkle_bin/generate_appcast"
generate_keys="$sparkle_bin/generate_keys"

if [[ ! -x "$generate_appcast" || ! -x "$generate_keys" ]]; then
  printf 'error: Sparkle tools were not found under %s\n' "$sparkle_bin" >&2
  exit 1
fi

if [[ -z "$sparkle_public_ed_key" ]]; then
  if ! sparkle_public_ed_key="$("$generate_keys" --account "$sparkle_account" -p 2>/dev/null)"; then
    printf 'error: no Sparkle public key found for account %s.\n' "$sparkle_account" >&2
    printf 'run: %s --account %s\n' "$generate_keys" "$sparkle_account" >&2
    printf 'then rerun this script or pass LATTICE_SPARKLE_PUBLIC_ED_KEY explicitly.\n' >&2
    exit 1
  fi
fi

mkdir -p "$update_dir"

LATTICE_ARTIFACT_DIR="$update_dir" \
LATTICE_MAC_APP_ARTIFACT="$artifact" \
LATTICE_SPARKLE_FEED_URL="$sparkle_feed_url" \
LATTICE_SPARKLE_PUBLIC_ED_KEY="$sparkle_public_ed_key" \
LATTICE_CODESIGN_IDENTITY="${codesign_identity:--}" \
LATTICE_ALLOW_ADHOC_UPDATE_SIGNATURE="$allow_adhoc_update_signature" \
bash "$repo_root/scripts/package-mac-app.sh" >/dev/null

appcast_args=()
if [[ -n "$sparkle_private_ed_key_file" ]]; then
  appcast_args+=(--ed-key-file "$sparkle_private_ed_key_file")
else
  appcast_args+=(--account "$sparkle_account")
fi

if [[ -n "$download_url_prefix" ]]; then
  download_url_prefix="${download_url_prefix%/}/"
  appcast_args+=(--download-url-prefix "$download_url_prefix")
fi

"$generate_appcast" "${appcast_args[@]}" -o "$update_dir/$appcast_name" "$update_dir"

printf 'Update archive: %s/%s.zip\n' "$update_dir" "$artifact"
printf 'Appcast: %s/%s\n' "$update_dir" "$appcast_name"
