#!/bin/sh
set -eu

repo="${LATTICE_REPO:-ejohane/lattice}"
version="${LATTICE_VERSION:-latest}"
install_dir="${LATTICE_APP_INSTALL_DIR:-$HOME/Applications}"
download_base_url="${LATTICE_DOWNLOAD_BASE_URL:-}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

download() {
  url="$1"
  output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$output"
  else
    printf 'error: required command not found: curl or wget\n' >&2
    exit 1
  fi
}

verify_checksum() {
  file="$1"
  checksum="$2"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "$checksum"
  else
    printf 'warning: shasum not found; skipping checksum verification\n' >&2
    return 0
  fi
}

register_app() {
  app="$1"
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  if [ -x "$lsregister" ]; then
    "$lsregister" -f "$app" >/dev/null 2>&1 || true
  fi
}

detect_artifact() {
  os="$(uname -s)"
  arch="$(uname -m)"

  if [ "$os" != "Darwin" ]; then
    printf 'error: the Lattice macOS app installer only supports macOS.\n' >&2
    exit 1
  fi

  case "$arch" in
    arm64|aarch64) printf 'lattice-macos-app-darwin-arm64' ;;
    x86_64|amd64) printf 'lattice-macos-app-darwin-x64' ;;
    *) printf 'error: unsupported macOS architecture: %s\n' "$arch" >&2; exit 1 ;;
  esac
}

need_cmd uname
need_cmd unzip

artifact="$(detect_artifact)"
archive="$artifact.zip"
checksum="$archive.sha256"

if [ -n "$download_base_url" ]; then
  base_url="$download_base_url"
elif [ "$version" = "latest" ]; then
  base_url="https://github.com/$repo/releases/latest/download"
else
  base_url="https://github.com/$repo/releases/download/$version"
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t lattice-app-install)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

printf 'Installing Lattice macOS app from %s/%s\n' "$repo" "$version"
printf 'Artifact: %s\n' "$archive"

download "$base_url/$archive" "$tmp_dir/$archive"
download "$base_url/$checksum" "$tmp_dir/$checksum"

(
  cd "$tmp_dir"
  verify_checksum "$archive" "$checksum"
  unzip -q "$archive"
)

if [ ! -d "$tmp_dir/Lattice.app" ]; then
  printf 'error: archive did not contain Lattice.app\n' >&2
  exit 1
fi

mkdir -p "$install_dir"
rm -rf "$install_dir/Lattice.app"
cp -R "$tmp_dir/Lattice.app" "$install_dir/Lattice.app"
register_app "$install_dir/Lattice.app"

printf 'Installed %s\n' "$install_dir/Lattice.app"
printf 'Open it with: open %s\n' "$install_dir/Lattice.app"
