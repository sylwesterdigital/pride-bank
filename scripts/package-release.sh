#!/bin/zsh
set -e
set -u
set -o pipefail

# Keep standard macOS/Linux system tools available even under customized shells.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT_DIR="${OUT_DIR:-$ROOT/archive}"
SHELL_BIN="${SHELL_BIN:-$(command -v zsh 2>/dev/null || command -v bash)}"
OUT="$OUT_DIR/pride-bank-v${VERSION}.zip"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pride-bank-package.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Invalid VERSION: $VERSION" >&2; exit 1; }
"$SHELL_BIN" "$ROOT/scripts/verify.sh"
mkdir -p "$OUT_DIR" "$TMP/repo"

rsync \
  --archive \
  --checksum \
  --exclude='.git/' \
  --exclude='archive/' \
  --exclude='.watch-state/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='data/' \
  --exclude='uploads/' \
  --exclude='logs/' \
  --exclude='.DS_Store' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  "$ROOT/" "$TMP/repo/"

rm -f "$OUT"
( cd "$TMP/repo" && /usr/bin/zip -qry "$OUT" . )
python3 "$ROOT/scripts/verify-archive.py" "$OUT"
echo "Created $OUT"
