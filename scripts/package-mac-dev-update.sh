#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_path="$repo_root/apps/Lattice/Lattice.xcworkspace"
scheme="LatticeMac"
derived_data_path="${LATTICE_DERIVED_DATA_PATH:-$repo_root/.build/xcode}"
sparkle_account="${LATTICE_SPARKLE_ACCOUNT:-lattice-dev}"
sparkle_feed_url="${LATTICE_SPARKLE_FEED_URL:-}"
sparkle_public_ed_key="${LATTICE_SPARKLE_PUBLIC_ED_KEY:-}"
sparkle_private_ed_key_file="${LATTICE_SPARKLE_PRIVATE_ED_KEY_FILE:-}"
download_url_prefix="${LATTICE_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
update_dir="${LATTICE_SPARKLE_UPDATE_DIR:-$repo_root/dist/sparkle-dev}"
artifact="${LATTICE_MAC_APP_ARTIFACT:-lattice-macos-app-dev}"
appcast_name="${LATTICE_SPARKLE_APPCAST_NAME:-appcast.xml}"

if [[ -z "$sparkle_feed_url" ]]; then
  printf 'error: set LATTICE_SPARKLE_FEED_URL to the development appcast URL.\n' >&2
  printf 'example: LATTICE_SPARKLE_FEED_URL=http://localhost:8000/appcast.xml %s\n' "$0" >&2
  exit 1
fi

resolve_sparkle_tool() {
  local tool_name="$1"
  local artifacts_dir="$derived_data_path/SourcePackages/artifacts"
  local tool_path=""

  if [[ -n "${LATTICE_SPARKLE_BIN:-}" && -x "${LATTICE_SPARKLE_BIN}/$tool_name" ]]; then
    printf '%s\n' "${LATTICE_SPARKLE_BIN}/$tool_name"
    return 0
  fi

  if [[ -d "$artifacts_dir" ]]; then
    tool_path="$(find "$artifacts_dir" -path "*/Sparkle/bin/$tool_name" -type f -perm -111 -print -quit 2>/dev/null || true)"
  fi

  if [[ -z "$tool_path" ]]; then
    xcodebuild \
      -resolvePackageDependencies \
      -workspace "$workspace_path" \
      -scheme "$scheme" \
      -derivedDataPath "$derived_data_path" >/dev/null
    tool_path="$(find "$artifacts_dir" -path "*/Sparkle/bin/$tool_name" -type f -perm -111 -print -quit 2>/dev/null || true)"
  fi

  if [[ -z "$tool_path" ]]; then
    printf 'error: Sparkle tool not found: %s\n' "$tool_name" >&2
    printf 'looked under: %s\n' "$artifacts_dir" >&2
    exit 1
  fi

  printf '%s\n' "$tool_path"
}

generate_appcast="$(resolve_sparkle_tool generate_appcast)"
generate_keys="$(resolve_sparkle_tool generate_keys)"

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
