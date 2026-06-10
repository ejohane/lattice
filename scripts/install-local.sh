#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

binary="${LATTICE_BINARY:-dist/lattice}"
install_dir="${LATTICE_INSTALL_DIR:-$HOME/.local/bin}"

if [[ ! -x "$binary" ]]; then
  LATTICE_OUTFILE="$binary" bash scripts/build-binary.sh >/dev/null
fi

mkdir -p "$install_dir"
cp "$binary" "$install_dir/lattice"
chmod +x "$install_dir/lattice"

printf 'Installed lattice to %s\n' "$install_dir/lattice"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    printf 'Note: %s is not currently on PATH.\n' "$install_dir"
    ;;
esac
