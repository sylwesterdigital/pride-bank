#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export GIT_PAGER=cat PAGER=cat GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true GIT_TERMINAL_PROMPT=0
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/scripts/terminal_style.sh"
cd "$ROOT"
EXPECTED_REMOTE="${EXPECTED_REMOTE:-git@github.com:sylwesterdigital/pride-bank.git}"
BRANCH="${RELEASE_BRANCH:-main}"
VERSION="$(tr -d '[:space:]' < VERSION)"
log(){ pb_section "$*"; }
fail(){ pb_error "$*"; exit 1; }
network_retry(){ local n=1 max="${PB_NETWORK_ATTEMPTS:-8}" delay="${PB_NETWORK_RETRY_DELAY:-8}"; until "$@"; do local rc=$?; (( n >= max )) && return "$rc"; pb_warn "Network operation failed; retry $n/$max in ${delay}s: $*"; sleep "$delay"; n=$((n+1)); done; }
[[ "$(uname -s)" == Darwin ]] || fail "Pride releases must run on the macOS development machine."
for t in git rsync ssh python3 xcodebuild; do command -v "$t" >/dev/null 2>&1 || fail "Required release tool missing: $t"; done
[[ -d .git ]] || fail "$ROOT is not a Git checkout."
[[ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$BRANCH" ]] || fail "Release must run on branch $BRANCH."
[[ -z "$(git diff --name-only --diff-filter=U)" ]] || fail "Resolve Git conflicts before release."
CURRENT_REMOTE="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$CURRENT_REMOTE" ]]; then git remote add origin "$EXPECTED_REMOTE"; elif [[ "$CURRENT_REMOTE" != "$EXPECTED_REMOTE" ]]; then git remote set-url origin "$EXPECTED_REMOTE"; fi
network_retry git ls-remote origin HEAD >/dev/null 2>&1 || fail "Git SSH access to $EXPECTED_REMOTE failed after retries."
log "Repository verification"
./scripts/verify_repo.sh
source ./scripts/release_profile.sh
pb_load_release_profile
network_retry ssh -o BatchMode=yes -o ConnectTimeout=12 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST" true || fail "Server SSH access failed after retries."
log "Committing release source"
git add -A
if git diff --cached --quiet; then log "No source changes to commit; using existing HEAD."; else git commit -m "Release v$VERSION"; fi
log "Pushing $BRANCH"
network_retry git push origin "$BRANCH"
log "Deploying Pride homepage/system"
./scripts/deploy_homepage.sh
log "Bootstrapping / deploying Pride Blocks API"
./scripts/deploy_backend.sh
log "Building / installing mobile app against verified API"
./scripts/app_build.sh
pb_banner_success "PRIDE RELEASE v$VERSION COMPLETED SUCCESSFULLY"
pb_field "GitHub:" "git@github.com:sylwesterdigital/pride-bank.git"
pb_field "Public web:" "$PB_REMOTE_DIR"
pb_field "Backend:" "/opt/pride-bank/current"
