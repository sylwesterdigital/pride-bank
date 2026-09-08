#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(pwd)"; ZIP="${1:-}"
[[ -n "$ZIP" && -f "$ZIP" ]] || { echo "Release ZIP not found: ${ZIP:-<missing>}" >&2; exit 2; }
[[ -d "$ROOT/.git" ]] || { echo "Run this from the pride-bank Git repository root." >&2; exit 1; }
mkdir -p "$ROOT/scripts" "$ROOT/archive"
for file in terminal_style.sh build-watch.sh; do unzip -p "$ZIP" "scripts/$file" > "$ROOT/scripts/$file" || exit 1; done
chmod +x "$ROOT/scripts/"*.sh
exec /bin/zsh "$ROOT/scripts/build-watch.sh"
