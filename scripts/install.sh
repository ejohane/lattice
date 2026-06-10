#!/bin/sh
set -eu

repo="${LATTICE_REPO:-ejohane/lattice}"
version="${LATTICE_VERSION:-latest}"
install_dir="${LATTICE_INSTALL_DIR:-$HOME/.local/bin}"
binary_name="${LATTICE_BINARY_NAME:-lattice}"
download_base_url="${LATTICE_DOWNLOAD_BASE_URL:-}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

detect_artifact() {
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin)
      case "$arch" in
        arm64|aarch64) printf 'lattice-darwin-arm64' ;;
        x86_64|amd64) printf 'lattice-darwin-x64' ;;
        *) printf 'error: unsupported macOS architecture: %s\n' "$arch" >&2; exit 1 ;;
      esac
      ;;
    Linux)
      case "$arch" in
        x86_64|amd64) printf 'lattice-linux-x64' ;;
        *) printf 'error: unsupported Linux architecture: %s\n' "$arch" >&2; exit 1 ;;
      esac
      ;;
    *)
      printf 'error: unsupported operating system: %s\n' "$os" >&2
      exit 1
      ;;
  esac
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
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$checksum"
  else
    printf 'warning: shasum or sha256sum not found; skipping checksum verification\n' >&2
    return 0
  fi
}

need_cmd uname
need_cmd tar

artifact="$(detect_artifact)"
archive="$artifact.tar.gz"
checksum="$archive.sha256"

if [ -n "$download_base_url" ]; then
  base_url="$download_base_url"
elif [ "$version" = "latest" ]; then
  base_url="https://github.com/$repo/releases/latest/download"
else
  base_url="https://github.com/$repo/releases/download/$version"
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t lattice-install)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

printf 'Installing Lattice from %s/%s\n' "$repo" "$version"
printf 'Artifact: %s\n' "$archive"

download "$base_url/$archive" "$tmp_dir/$archive"
download "$base_url/$checksum" "$tmp_dir/$checksum"

(
  cd "$tmp_dir"
  verify_checksum "$archive" "$checksum"
  tar -xzf "$archive"
)

if [ ! -f "$tmp_dir/$artifact/lattice" ]; then
  printf 'error: archive did not contain %s/lattice\n' "$artifact" >&2
  exit 1
fi

mkdir -p "$install_dir"
cp "$tmp_dir/$artifact/lattice" "$install_dir/$binary_name"
chmod 0755 "$install_dir/$binary_name"

printf 'Installed %s\n' "$install_dir/$binary_name"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    printf 'Note: %s is not currently on PATH.\n' "$install_dir"
    ;;
esac
