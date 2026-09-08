#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/scripts/terminal_style.sh"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
ARCHIVE_DIR="${ARCHIVE_DIR:-$ROOT/archive}"
OUT="$ARCHIVE_DIR/pride-bank-v${VERSION}.zip"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pride-bank-package.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { pb_error "Invalid VERSION: $VERSION"; exit 1; }
"$ROOT/scripts/verify_repo.sh"
mkdir -p "$ARCHIVE_DIR" "$TMP/repo"
rsync --archive --checksum --exclude='archive/' --exclude='.watch-state/' --exclude='build/' --exclude='.git/' --exclude='.DS_Store' --exclude='xcuserdata/' --exclude='*.xcuserstate' --exclude='.env' --exclude='.env.*' --exclude='__pycache__/' --exclude='*.pyc' "$ROOT/" "$TMP/repo/"
rm -f "$OUT"
( cd "$TMP/repo" && /usr/bin/zip -qry "$OUT" . )
pb_success "Release source package created"
pb_field "ZIP:" "$OUT"
