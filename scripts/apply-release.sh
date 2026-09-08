#!/bin/zsh
# Apply an already-extracted complete release snapshot to this repository.
set -e
set -u
set -o pipefail

# Keep standard macOS/Linux system tools available even under customized shells.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/terminal-style.sh"
SHELL_BIN="${SHELL_BIN:-$(command -v zsh 2>/dev/null || command -v bash)}"

SOURCE_DIR="${1:-}"
[[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]] || { pb_error "Usage: ./scripts/apply-release.sh <extracted-release-dir>"; exit 2; }
[[ -f "$SOURCE_DIR/VERSION" ]] || { pb_error "Release is missing VERSION"; exit 1; }

pb_info "Synchronising release into repository"
rsync \
  --archive \
  --checksum \
  --delete \
  --exclude='.git/' \
  --exclude='archive/' \
  --exclude='.watch-state/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='data/' \
  --exclude='uploads/' \
  --exclude='logs/' \
  "$SOURCE_DIR/" "$ROOT/"

"$SHELL_BIN" "$ROOT/scripts/verify.sh"
pb_ok "Release applied successfully"
