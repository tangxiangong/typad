#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-run}"
case "$mode" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
# Explicitly invoked by the user. Close document windows before using this restart loop.
if pgrep -x TyPad >/dev/null; then
    echo "Save your documents and quit TyPad before restarting." >&2
    exit 1
fi
bash "$repo/macos/build.sh"
app="$repo/target/xcode/Build/Products/Debug/TyPad.app"
case "$mode" in
    --debug) exec lldb -- "$app/Contents/MacOS/TyPad";;
    --logs|--telemetry) open -n "$app"; exec /usr/bin/log stream --info --style compact --predicate 'process == "TyPad"';;
    --verify) open -n "$app"; sleep 1; pgrep -x TyPad >/dev/null;;
    run) open -n "$app";;
esac
