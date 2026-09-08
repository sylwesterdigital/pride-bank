#!/bin/zsh
# One-time bootstrap for a repository that does not yet contain the watcher.
# Intended usage from the repository root:
# unzip -p archive/pride-bank-v0.1.1.zip scripts/bootstrap-watch.sh | zsh -s -- archive/pride-bank-v0.1.1.zip
set -e
set -u
set -o pipefail

# Keep standard macOS/Linux system tools available even under customized shells.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT="$(pwd)"
ZIP="${1:-}"

[[ -n "$ZIP" && -f "$ZIP" ]] || { echo "Release ZIP not found: ${ZIP:-<missing>}" >&2; exit 2; }
[[ -d "$ROOT/.git" ]] || { echo "Run this from the root of the pride-bank Git repository." >&2; exit 1; }

if [[ -f "$ROOT/scripts/build-watch.sh" ]]; then
  echo "Watcher already exists. Run: ./scripts/build-watch.sh" >&2
  exit 1
fi

mkdir -p "$ROOT/scripts" "$ROOT/archive"

for file in terminal-style.sh verify-archive.py apply-release.sh build-watch.sh; do
  unzip -p "$ZIP" "scripts/$file" > "$ROOT/scripts/$file" || {
    echo "Could not extract scripts/$file from $ZIP" >&2
    exit 1
  }
done
chmod +x "$ROOT/scripts/"*.sh "$ROOT/scripts/"*.py

python3 "$ROOT/scripts/verify-archive.py" "$ZIP"

SHELL_BIN="${SHELL_BIN:-$(command -v zsh 2>/dev/null || command -v bash)}"
echo "Watcher installed. Applying ${ZIP##*/} through the archive workflow."
exec "$SHELL_BIN" "$ROOT/scripts/build-watch.sh"
