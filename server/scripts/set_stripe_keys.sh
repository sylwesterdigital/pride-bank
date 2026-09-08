#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE=/etc/pride-bank/server.env
[[ "$(id -u)" -eq 0 ]] || { echo 'ERROR: root required' >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo 'ERROR: Pride server.env does not exist yet' >&2; exit 1; }
IFS= read -r SECRET
IFS= read -r PUBLISHABLE
[[ "$SECRET" =~ ^sk_(test|live)_[A-Za-z0-9_]+$ ]] || { echo 'ERROR: invalid Stripe secret key format' >&2; exit 1; }
MODE="${BASH_REMATCH[1]}"
[[ "$PUBLISHABLE" =~ ^pk_${MODE}_[A-Za-z0-9_]+$ ]] || { echo "ERROR: publishable key must be a pk_${MODE}_ key" >&2; exit 1; }
umask 077
TMP="$(mktemp /etc/pride-bank/server.env.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
SEEN_SECRET=0; SEEN_PUB=0; SEEN_MODE=0
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    STRIPE_SECRET_KEY=*) printf 'STRIPE_SECRET_KEY=%s\n' "$SECRET" >> "$TMP"; SEEN_SECRET=1 ;;
    STRIPE_PUBLISHABLE_KEY=*) printf 'STRIPE_PUBLISHABLE_KEY=%s\n' "$PUBLISHABLE" >> "$TMP"; SEEN_PUB=1 ;;
    STRIPE_MODE=*) printf 'STRIPE_MODE=%s\n' "$MODE" >> "$TMP"; SEEN_MODE=1 ;;
    *) printf '%s\n' "$line" >> "$TMP" ;;
  esac
done < "$ENV_FILE"
(( SEEN_SECRET )) || printf 'STRIPE_SECRET_KEY=%s\n' "$SECRET" >> "$TMP"
(( SEEN_PUB )) || printf 'STRIPE_PUBLISHABLE_KEY=%s\n' "$PUBLISHABLE" >> "$TMP"
(( SEEN_MODE )) || printf 'STRIPE_MODE=%s\n' "$MODE" >> "$TMP"
chown root:root "$TMP"
chmod 600 "$TMP"
mv -f "$TMP" "$ENV_FILE"
trap - EXIT
unset SECRET PUBLISHABLE
printf 'STRIPE_KEYS_STORED=1\n'
