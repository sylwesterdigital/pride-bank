#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/scripts/terminal_style.sh"
source "$ROOT/scripts/release_profile.sh"
cd "$ROOT"; pb_load_release_profile
VERSION="$(tr -d '[:space:]' < VERSION)"
fail(){ pb_error "$*"; exit 1; }
for t in rsync ssh mktemp; do command -v "$t" >/dev/null || fail "Missing tool: $t"; done
REMOTE_TARGET="${TMPDIR_REMOTE:-/tmp}/pride-bank-server-${VERSION}-$$"
REMOTE_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 -p "$PB_REMOTE_PORT" "$PB_REMOTE_USER@$PB_REMOTE_HOST")
PREFERRED_PUBLIC_URL="${PB_REMOTE_URL:-https://mojoworks.xyz/labs/bank}"

pb_section "Staging Blocks API release on Ubuntu"
"${REMOTE_SSH[@]}" "rm -rf '$REMOTE_TARGET' && mkdir -p '$REMOTE_TARGET'"
rsync -az --checksum --delete --exclude='.env' --exclude='.env.*' --exclude='node_modules/' -e "ssh -o BatchMode=yes -o ConnectTimeout=15 -p $PB_REMOTE_PORT" "$ROOT/server/" "$PB_REMOTE_USER@$PB_REMOTE_HOST:$REMOTE_TARGET/"

pb_section "Safe Ubuntu infrastructure / backend bootstrap"
REMOTE_UID="$("${REMOTE_SSH[@]}" 'id -u')"
if [[ "$REMOTE_UID" == 0 ]]; then
  PRIV=""
elif "${REMOTE_SSH[@]}" 'sudo -n true' >/dev/null 2>&1; then
  PRIV="sudo -n"
else
  fail "Ubuntu bootstrap needs root or non-interactive sudo for Pride-specific /opt, /etc, systemd and PostgreSQL resources. Existing shared services will not be modified without those checks."
fi
if [[ -n "$PRIV" ]]; then
  PRIV_PREFIX="sudo -n"
else
  PRIV_PREFIX=""
fi
run_bootstrap(){
  local cmd
  if [[ -n "$PRIV_PREFIX" ]]; then
    cmd="sudo -n env PB_VERSION='$VERSION' PB_SOURCE_DIR='$REMOTE_TARGET' PB_PUBLIC_ROOT='$PB_REMOTE_DIR' PB_PREFERRED_PUBLIC_URL='$PREFERRED_PUBLIC_URL' bash '$REMOTE_TARGET/scripts/bootstrap_ubuntu.sh'"
  else
    cmd="env PB_VERSION='$VERSION' PB_SOURCE_DIR='$REMOTE_TARGET' PB_PUBLIC_ROOT='$PB_REMOTE_DIR' PB_PREFERRED_PUBLIC_URL='$PREFERRED_PUBLIC_URL' bash '$REMOTE_TARGET/scripts/bootstrap_ubuntu.sh'"
  fi
  set +e
  BOOT_OUTPUT="$("${REMOTE_SSH[@]}" "$cmd" 2>&1)"
  BOOT_RC=$?
  set -e
  printf '%s\n' "$BOOT_OUTPUT"
}
run_bootstrap
if (( BOOT_RC == 78 )) && [[ "$(printf '%s\n' "$BOOT_OUTPUT" | sed -n 's/^NEED_STRIPE_KEYS=//p' | tail -n1)" == 1 ]]; then
  if [[ -t 0 && -t 1 ]]; then
    echo
    pb_section "One-time Stripe account credentials"
    printf '%s' "Stripe secret key (input hidden): "
    IFS= read -r -s STRIPE_SECRET_INPUT
    echo
    printf '%s' "Stripe publishable key: "
    IFS= read -r STRIPE_PUBLISHABLE_INPUT
    [[ "$STRIPE_SECRET_INPUT" =~ ^sk_(test|live)_[A-Za-z0-9_]+$ ]] || fail "Stripe secret key format is invalid."
    STRIPE_INPUT_MODE="${match[1]}"
    [[ "$STRIPE_PUBLISHABLE_INPUT" == pk_${STRIPE_INPUT_MODE}_* ]] || fail "Stripe publishable key must use the same ${STRIPE_INPUT_MODE} mode."
    pb_section "Storing Stripe credentials root-only on Ubuntu"
    if [[ -n "$PRIV_PREFIX" ]]; then
      printf '%s\n%s\n' "$STRIPE_SECRET_INPUT" "$STRIPE_PUBLISHABLE_INPUT" | "${REMOTE_SSH[@]}" "sudo -n bash '$REMOTE_TARGET/scripts/set_stripe_keys.sh'" >/dev/null
    else
      printf '%s\n%s\n' "$STRIPE_SECRET_INPUT" "$STRIPE_PUBLISHABLE_INPUT" | "${REMOTE_SSH[@]}" "bash '$REMOTE_TARGET/scripts/set_stripe_keys.sh'" >/dev/null
    fi
    unset STRIPE_SECRET_INPUT STRIPE_PUBLISHABLE_INPUT
    pb_success "Stripe account keys stored without writing them to Git or command history. Continuing bootstrap."
    run_bootstrap
  fi
fi
if (( BOOT_RC == 78 )); then
  "${REMOTE_SSH[@]}" "rm -rf '$REMOTE_TARGET'" >/dev/null 2>&1 || true
  fail "Ubuntu Pride infrastructure was prepared safely, but an external boundary still needs attention. See ACTION_REQUIRED details above; the script refused to guess or rewrite ambiguous shared infrastructure."
elif (( BOOT_RC != 0 )); then
  "${REMOTE_SSH[@]}" "rm -rf '$REMOTE_TARGET'" >/dev/null 2>&1 || true
  fail "Ubuntu backend bootstrap/deployment failed."
fi
"${REMOTE_SSH[@]}" "rm -rf '$REMOTE_TARGET'" >/dev/null 2>&1 || true
API_BASE_URL="$(printf '%s\n' "$BOOT_OUTPUT" | sed -n 's/^PRIDE_API_BASE_URL=//p' | tail -n1)"
PUBLIC_URL="$(printf '%s\n' "$BOOT_OUTPUT" | sed -n 's/^PUBLIC_BASE_URL=//p' | tail -n1)"
[[ "$API_BASE_URL" == https://* ]] || fail "Backend reported no safe HTTPS API base URL."
PB_REMOTE_URL="$PUBLIC_URL"
PB_API_BASE_URL="$API_BASE_URL"
pb_write_profile
pb_success "Blocks API deployed and release profile updated with $PB_API_BASE_URL"
