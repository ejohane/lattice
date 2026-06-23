#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_path="$repo_root/apps/lattice"
configuration="${CONFIGURATION:-release}"
app_name="Lattice"
executable_name="Lattice"
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
dist_dir="$repo_root/dist"
app_dir="$dist_dir/$app_name.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
frameworks_dir="$contents_dir/Frameworks"

swift build --package-path "$package_path" -c "$configuration"
build_dir="$(swift build --package-path "$package_path" -c "$configuration" --show-bin-path)"

binary="$build_dir/$executable_name"
if [[ ! -x "$binary" ]]; then
  printf 'Missing built executable: %s\n' "$binary" >&2
  exit 1
fi

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir" "$frameworks_dir"
cp "$binary" "$macos_dir/$executable_name"
chmod 0755 "$macos_dir/$executable_name"

sparkle_framework="$build_dir/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
  printf 'Missing Sparkle framework: %s\n' "$sparkle_framework" >&2
  exit 1
fi

COPYFILE_DISABLE=1 ditto --norsrc "$sparkle_framework" "$frameworks_dir/Sparkle.framework"
if ! otool -l "$macos_dir/$executable_name" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$macos_dir/$executable_name"
fi

xml_escape() {
  printf '%s' "$1" \
    | sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' \
      -e "s/'/\&apos;/g"
}

{
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$executable_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(xml_escape "$app_version")</string>
  <key>CFBundleVersion</key>
  <string>$(xml_escape "$app_build")</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
PLIST

if [[ -n "$sparkle_feed_url" ]]; then
cat <<PLIST
  <key>SUFeedURL</key>
  <string>$(xml_escape "$sparkle_feed_url")</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
PLIST
fi

if [[ -n "$sparkle_public_ed_key" ]]; then
cat <<PLIST
  <key>SUPublicEDKey</key>
  <string>$(xml_escape "$sparkle_public_ed_key")</string>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
PLIST
fi

cat <<PLIST
</dict>
</plist>
PLIST
} > "$contents_dir/Info.plist"

if [[ -n "$codesign_identity" ]]; then
  codesign --force --deep --sign "$codesign_identity" "$app_dir"
fi

printf '%s\n' "$app_dir"
