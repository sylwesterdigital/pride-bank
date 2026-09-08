#!/bin/zsh
# Release/deployment entry point called by build-watch.sh.
set -e
set -u
set -o pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export GIT_PAGER=cat PAGER=cat GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/terminal-style.sh"
source "$SCRIPT_DIR/release_profile.sh"

EXPECTED_REMOTE="${EXPECTED_REMOTE:-git@github.com:sylwesterdigital/pride-bank.git}"
BRANCH="${RELEASE_BRANCH:-main}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

retry() {
  local max="$1" delay="$2"
  shift 2
  local attempt=1
  until "$@"; do
    local rc=$?
    if (( attempt >= max )); then
      return "$rc"
    fi
    pb_warn "Network operation failed; retry $attempt/$max in ${delay}s."
    sleep "$delay"
    (( attempt += 1 ))
  done
}

fail() { pb_error "$*"; exit 1; }

for tool_name in git rsync ssh python3; do
  command -v "$tool_name" >/dev/null 2>&1 || fail "Required deployment tool missing: $tool_name"
done

[[ -d "$ROOT/.git" ]] || fail "$ROOT is not a Git checkout."
[[ "$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$BRANCH" ]] || fail "Release must run on branch $BRANCH."
[[ -z "$(git -C "$ROOT" diff --name-only --diff-filter=U)" ]] || fail "Resolve Git conflicts before deployment."

pb_info "Repository verification"
"$ROOT/scripts/verify.sh"

pb_load_release_profile
pb_info "Deployment target: $PB_REMOTE_HOST:$PB_REMOTE_DIR"
retry 4 5 ssh -o BatchMode=yes -o ConnectTimeout=12 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" true \
  || fail "SSH access to deployment host failed."

current_remote="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
if [[ -z "$current_remote" ]]; then
  git -C "$ROOT" remote add origin "$EXPECTED_REMOTE"
elif [[ "$current_remote" != "$EXPECTED_REMOTE" ]]; then
  fail "Unexpected Git origin: $current_remote"
fi

pb_info "Committing release source"
git -C "$ROOT" add -A
if git -C "$ROOT" diff --cached --quiet; then
  pb_info "No source changes to commit; using existing HEAD."
else
  git -C "$ROOT" commit -m "Release v$VERSION"
fi

pb_info "Pushing $BRANCH"
retry 4 5 git -C "$ROOT" push origin "$BRANCH" || fail "Git push failed."

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pride-bank-deploy.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
rsync --archive --checksum "$ROOT/web/" "$BUILD_DIR/"
printf '%s\n' "$VERSION" > "$BUILD_DIR/VERSION"
python3 - "$BUILD_DIR/deployment.json" "$VERSION" <<'PY'
from pathlib import Path
import json, sys
Path(sys.argv[1]).write_text(json.dumps({"product":"Pride Bank / Blocks","version":sys.argv[2]}, indent=2)+"\n")
PY

pb_info "Deploying web release to $PB_REMOTE_DIR"
retry 4 5 ssh -o BatchMode=yes -o ConnectTimeout=12 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" \
  "mkdir -p '$PB_REMOTE_DIR'" || fail "Could not prepare remote directory."

rsync_flags=(
  --archive
  --compress
  --human-readable
  --itemize-changes
  --checksum
  --delete-delay
  --delay-updates
  --partial
  --partial-dir=.rsync-partial
  --chmod="$PB_REMOTE_CHMOD"
)
if rsync --help 2>&1 | grep -q -- '--chown'; then
  rsync_flags+=(--chown="$PB_REMOTE_OWNER")
fi

retry 4 7 rsync "${rsync_flags[@]}" \
  -e "ssh -o BatchMode=yes -o ConnectTimeout=12 -p $PB_REMOTE_PORT" \
  "$BUILD_DIR/" "$PB_REMOTE_USER@$PB_REMOTE_HOST:$PB_REMOTE_DIR/" \
  || fail "Remote rsync failed."

remote_version="$(ssh -o BatchMode=yes -o ConnectTimeout=12 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" "cat '$PB_REMOTE_DIR/VERSION' 2>/dev/null" || true)"
[[ "$remote_version" == "$VERSION" ]] || fail "Remote VERSION verification failed: expected $VERSION, got ${remote_version:-<missing>}"

if [[ -n "${PB_REMOTE_URL:-}" ]] && command -v curl >/dev/null 2>&1; then
  verify_file="$(mktemp "${TMPDIR:-/tmp}/pride-bank-public.XXXXXX")"
  if retry 4 5 curl --fail --silent --show-error --location "${PB_REMOTE_URL%/}/?release=$VERSION" -o "$verify_file"; then
    grep -Fq 'Blocks' "$verify_file" || fail "Public page responded but Blocks verification failed."
    pb_ok "Public page verified: $PB_REMOTE_URL"
  else
    rm -f "$verify_file"
    fail "Public URL verification failed: $PB_REMOTE_URL"
  fi
  rm -f "$verify_file"
fi

pb_ok "Pride Bank v$VERSION deployed successfully."
