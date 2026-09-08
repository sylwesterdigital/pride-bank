#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE=/etc/pride-bank/server.env
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ENV_TOOL="$SCRIPT_DIR/env_file.py"
[[ "$(id -u)" -eq 0 ]] || { echo 'ERROR: root required' >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo 'ERROR: Pride server.env does not exist yet' >&2; exit 1; }
[[ -r "$ENV_TOOL" ]] || { echo 'ERROR: safe Pride environment parser missing' >&2; exit 1; }
IFS= read -r SECRET
IFS= read -r PUBLISHABLE
[[ "$SECRET" =~ ^sk_(test|live)_[A-Za-z0-9_]+$ ]] || { echo 'ERROR: invalid Stripe secret key format' >&2; exit 1; }
MODE="${BASH_REMATCH[1]}"
[[ "$PUBLISHABLE" =~ ^pk_${MODE}_[A-Za-z0-9_]+$ ]] || { echo "ERROR: publishable key must be a pk_${MODE}_ key" >&2; exit 1; }
printf 'STRIPE_SECRET_KEY=%s\nSTRIPE_PUBLISHABLE_KEY=%s\nSTRIPE_MODE=%s\n' "$SECRET" "$PUBLISHABLE" "$MODE" | python3 "$ENV_TOOL" set-many-stdin "$ENV_FILE"
python3 "$ENV_TOOL" validate "$ENV_FILE" >/dev/null
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"
unset SECRET PUBLISHABLE
printf 'STRIPE_KEYS_STORED=1\n'
