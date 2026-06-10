#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

target="${LATTICE_TARGET:-${1:-}}"
outfile="${LATTICE_OUTFILE:-}"

if [[ -z "$outfile" ]]; then
  if [[ -n "$target" ]]; then
    outfile="dist/lattice-${target#bun-}"
  else
    outfile="dist/lattice"
  fi
fi

mkdir -p "$(dirname "$outfile")"

args=(build --compile --minify src/cli.ts --outfile "$outfile")
if [[ -n "$target" ]]; then
  args=(build --compile --minify --target "$target" src/cli.ts --outfile "$outfile")
fi

bun "${args[@]}"
chmod +x "$outfile" 2>/dev/null || true
printf '%s\n' "$outfile"
