#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
app_name="Lattice"
bundle_id="com.ejohane.lattice"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$repo_root/dist/$app_name.app"
app_binary="$app_bundle/Contents/MacOS/$app_name"

case "$mode" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

pkill -x "$app_name" >/dev/null 2>&1 || true
(cd "$repo_root" && bun run mac:bundle)

open_app() {
  /usr/bin/open -n "$app_bundle"
}

case "$mode" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$app_binary"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$app_name\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$app_name" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$app_name did not launch." >&2
    exit 1
    ;;
esac
