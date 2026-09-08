#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/scripts/terminal_style.sh"
source "$ROOT/scripts/release_profile.sh"
cd "$ROOT"
pb_load_release_profile
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_ROOT="$ROOT/build/homepage"
STAMP="$(date +%Y%m%d%H%M%S)"
BUILD_DIR="$BUILD_ROOT/pride-bank-$STAMP"
log(){ pb_section "$*"; }
fail(){ pb_error "$*"; exit 1; }
retry(){ local n=1 max="$1" delay="$2"; shift 2; until "$@"; do local rc=$?; (( n >= max )) && return "$rc"; pb_warn "retry $n/$max in ${delay}s: $*"; sleep "$delay"; n=$((n+1)); done; }
for t in rsync ssh python3; do command -v "$t" >/dev/null 2>&1 || fail "Missing tool: $t"; done
[[ -f homepage/index.html ]] || fail "homepage/index.html missing"
[[ -f homepage/app.css ]] || fail "homepage/app.css missing"
[[ -f homepage/app.js ]] || fail "homepage/app.js missing"
mkdir -p "$BUILD_DIR"
rsync --archive --checksum --delete "$ROOT/homepage/" "$BUILD_DIR/"
printf '%s\n' "$VERSION" > "$BUILD_DIR/VERSION"
python3 - "$BUILD_DIR/release.json" "$VERSION" <<'PY'
from pathlib import Path
import json,sys
Path(sys.argv[1]).write_text(json.dumps({'product':'Pride','unit':'Blocks','version':sys.argv[2]},indent=2)+'\n')
PY
log "Deploying Pride to $PB_REMOTE_HOST:$PB_REMOTE_DIR"
retry 4 8 ssh -o BatchMode=yes -o ConnectTimeout=15 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" "mkdir -p '$PB_REMOTE_DIR'"
flags=(-avz --human-readable --itemize-changes --checksum --chmod="$PB_REMOTE_CHMOD" --partial --partial-dir=.rsync-partial --delay-updates --delete-delay)
if rsync --help 2>&1 | grep -q -- '--chown'; then flags+=(--chown="$PB_REMOTE_OWNER"); fi
retry 4 10 rsync "${flags[@]}" -e "ssh -o BatchMode=yes -o ConnectTimeout=15 -p $PB_REMOTE_PORT" "$BUILD_DIR/" "$PB_REMOTE_USER@$PB_REMOTE_HOST:$PB_REMOTE_DIR/"
log "Verifying remote deployment"
REMOTE_VERSION="$(ssh -o BatchMode=yes -o ConnectTimeout=15 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" "cat '$PB_REMOTE_DIR/VERSION' 2>/dev/null" || true)"
[[ "$REMOTE_VERSION" == "$VERSION" ]] || fail "Remote VERSION mismatch: expected $VERSION, got ${REMOTE_VERSION:-<missing>}"
ssh -o BatchMode=yes -o ConnectTimeout=15 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" "grep -Fq '<title>Pride — Blocks</title>' '$PB_REMOTE_DIR/index.html'" || fail "Remote homepage verification failed."
if [[ -n "${PB_REMOTE_URL:-}" ]] && command -v curl >/dev/null 2>&1; then
  TMP="$(mktemp "${TMPDIR:-/tmp}/pride-bank-public.XXXXXX")"; trap 'rm -f "$TMP"' EXIT
  retry 4 8 curl --fail --silent --show-error --location "${PB_REMOTE_URL%/}/?deploy=$STAMP" -o "$TMP"
  grep -Fq '<title>Pride — Blocks</title>' "$TMP" || fail "Public homepage title verification failed."
  pb_success "Public page verified: $PB_REMOTE_URL"
fi
pb_success "Homepage deployed and verified at $PB_REMOTE_DIR"
