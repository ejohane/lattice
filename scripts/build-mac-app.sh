#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_path="$repo_root/apps/Lattice/Lattice.xcworkspace"
scheme="LatticeMac"
configuration="${CONFIGURATION:-Release}"
app_name="Lattice"
bundle_id="${LATTICE_BUNDLE_ID:-com.ejohane.lattice}"
if [[ -n "${LATTICE_APP_VERSION:-}" ]]; then
  app_version="$LATTICE_APP_VERSION"
elif command -v node >/dev/null 2>&1; then
  app_version="$(node -e "console.log(require('./package.json').version)")"
else
  app_version="$(bun -e "console.log(require('./package.json').version)")"
fi
app_build="${LATTICE_APP_BUILD:-1}"
sparkle_feed_url="${LATTICE_SPARKLE_FEED_URL:-}"
sparkle_public_ed_key="${LATTICE_SPARKLE_PUBLIC_ED_KEY:-}"
codesign_identity="${LATTICE_CODESIGN_IDENTITY:--}"
derived_data_path="${LATTICE_DERIVED_DATA_PATH:-$repo_root/.build/xcode}"
dist_dir="$repo_root/dist"
app_dir="$dist_dir/$app_name.app"

xcodebuild \
  -workspace "$workspace_path" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  MARKETING_VERSION="$app_version" \
  CURRENT_PROJECT_VERSION="$app_build" \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  LATTICE_SPARKLE_FEED_URL="$sparkle_feed_url" \
  LATTICE_SPARKLE_PUBLIC_ED_KEY="$sparkle_public_ed_key" \
  build

built_app="$derived_data_path/Build/Products/$configuration/$app_name.app"
if [[ ! -d "$built_app" ]]; then
  printf 'Missing built app: %s\n' "$built_app" >&2
  exit 1
fi

rm -rf "$app_dir"
ditto "$built_app" "$app_dir"

if [[ -n "$codesign_identity" ]]; then
  codesign --force --deep --sign "$codesign_identity" "$app_dir"
fi

printf '%s\n' "$app_dir"
