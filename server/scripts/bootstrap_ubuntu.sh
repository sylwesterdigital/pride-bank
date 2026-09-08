#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
# Use a neutral locale for subprocesses without changing host locale configuration.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
unset LANGUAGE LC_CTYPE 2>/dev/null || true
RELEASE_VERSION="${PB_VERSION:?PB_VERSION missing}"
SOURCE_DIR="${PB_SOURCE_DIR:?PB_SOURCE_DIR missing}"
PUBLIC_ROOT="${PB_PUBLIC_ROOT:-/var/www/mojoworks/labs/bank}"
PREFERRED_PUBLIC_URL="${PB_PREFERRED_PUBLIC_URL:-}"
APP_ROOT=/opt/pride-bank
RELEASE_DIR="$APP_ROOT/releases/$RELEASE_VERSION"
CURRENT_LINK="$APP_ROOT/current"
ETC_DIR=/etc/pride-bank
STATE_DIR=/var/lib/pride-bank
BACKUP_DIR=/var/backups/pride-bank
ENV_FILE="$ETC_DIR/server.env"
ENV_TOOL="$SOURCE_DIR/scripts/env_file.py"
SERVICE_FILE=/etc/systemd/system/pride-blocks.service
SNIPPET=/etc/nginx/snippets/pride-bank-api.conf
MANUAL=0
NEED_STRIPE_KEYS=0
NEED_HTTPS_MAPPING=0

log(){ printf '\n==> %s\n' "$*"; }
ok(){ printf '✓ %s\n' "$*"; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# PostgreSQL commands always run from / so the postgres OS user never needs
# traverse access to the root-owned application release tree. stdin remains
# available for streamed SQL and pg_dump output is captured by the root shell.
as_postgres(){ ( cd / && runuser -u postgres -- "$@" ); }

if [[ "$(id -u)" -ne 0 ]]; then die "bootstrap_ubuntu.sh must run as root (the release script uses root or sudo -n)."; fi
[[ -r /etc/os-release ]] || die '/etc/os-release missing'
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "Refusing automatic host bootstrap on non-Ubuntu system: ${PRETTY_NAME:-unknown}"
command -v systemctl >/dev/null || die 'systemd is required'
mkdir -p "$ETC_DIR" "$STATE_DIR" "$BACKUP_DIR/postgres" "$BACKUP_DIR/nginx" "$APP_ROOT/releases"
chmod 750 "$ETC_DIR" "$STATE_DIR" "$BACKUP_DIR" "$BACKUP_DIR/postgres" "$BACKUP_DIR/nginx"
# /opt/pride-bank is application source, not secret material. Keep it root-owned
# but group-readable/traversable by only the dedicated service account.
chmod 750 "$APP_ROOT" "$APP_ROOT/releases"

log 'Host inventory (read-only)'
printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'Ubuntu: %s\n' "${VERSION_ID:-unknown}"
printf 'Existing nginx: %s\n' "$(command -v nginx || echo no)"
printf 'Existing node: %s\n' "$(command -v node >/dev/null && node --version || echo no)"
printf 'Existing psql: %s\n' "$(command -v psql || echo no)"

apt_install_if_absent(){
  local cmd="$1"; shift
  command -v "$cmd" >/dev/null 2>&1 && return 0
  log "Installing missing fresh-host prerequisite: $*"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends "$@"
}

apt_install_if_absent curl ca-certificates curl
apt_install_if_absent openssl openssl
apt_install_if_absent python3 python3
apt_install_if_absent node nodejs npm
apt_install_if_absent npm npm
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
(( NODE_MAJOR >= 18 )) || die "Existing Node.js $(node --version) is below 18. Refusing to replace/upgrade a shared system runtime automatically."

# PostgreSQL: reuse a healthy existing local cluster. Install only when PostgreSQL
# is genuinely absent. Never edit postgresql.conf or pg_hba.conf.
PG_NEW=0
if ! command -v psql >/dev/null 2>&1; then
  if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)5432$'; then
    die 'Port 5432 is already in use but PostgreSQL client tools are absent; refusing to install over an unknown database service.'
  fi
  log 'Installing PostgreSQL because no PostgreSQL installation was detected'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends postgresql postgresql-client
  PG_NEW=1
fi
command -v pg_isready >/dev/null || die 'pg_isready missing after PostgreSQL check'
if ! as_postgres psql -Atqc 'select current_database()' postgres >/dev/null 2>&1; then
  if (( PG_NEW )); then
    systemctl enable --now postgresql
  else
    die 'PostgreSQL is installed but the existing local cluster is not accepting local postgres connections. Refusing to start/change an existing cluster automatically.'
  fi
fi
as_postgres psql -Atqc 'select version()' postgres >/dev/null || die 'Local PostgreSQL safety check failed'
ok 'Existing/local PostgreSQL cluster is healthy; no global PostgreSQL configuration was changed.'

# Dedicated service identity. On a fresh shared host, do not silently reuse an
# unrelated pre-existing account with the same name.
if getent passwd pride-bank >/dev/null; then
  PB_HOME="$(getent passwd pride-bank | cut -d: -f6)"
  PB_SHELL="$(getent passwd pride-bank | cut -d: -f7)"
  if [[ ! -f "$STATE_DIR/managed" && ( "$PB_HOME" != "$STATE_DIR" || "$PB_SHELL" != /usr/sbin/nologin ) ]]; then
    die "OS user pride-bank already exists with unexpected home/shell; refusing a possible shared-host account collision."
  fi
else
  if ! getent group pride-bank >/dev/null; then groupadd --system pride-bank; fi
  useradd --system --gid pride-bank --home "$STATE_DIR" --shell /usr/sbin/nologin pride-bank
  ok 'Created dedicated pride-bank service user.'
fi
if ! getent group pride-bank >/dev/null; then
  groupadd --system pride-bank
  usermod -g pride-bank pride-bank
elif [[ "$(id -gn pride-bank)" != pride-bank ]]; then
  # This user is Pride-managed at this point; normalize only its own primary group.
  usermod -g pride-bank pride-bank
fi
chown root:pride-bank "$APP_ROOT" "$APP_ROOT/releases"
chmod 750 "$APP_ROOT" "$APP_ROOT/releases"
chown pride-bank:pride-bank "$STATE_DIR"
chmod 750 "$STATE_DIR"

# Detect collisions before touching app-specific DB resources. Pride uses a NOLOGIN
# owner role so the network-facing API role never owns ledger tables/functions.
ROLE_EXISTS="$(as_postgres psql -Atqc "select 1 from pg_roles where rolname='pride_app'" postgres || true)"
OWNER_ROLE_EXISTS="$(as_postgres psql -Atqc "select 1 from pg_roles where rolname='pride_owner'" postgres || true)"
DB_OWNER="$(as_postgres psql -Atqc "select pg_catalog.pg_get_userbyid(datdba) from pg_database where datname='pride_bank'" postgres || true)"
if [[ -n "$DB_OWNER" && "$DB_OWNER" != pride_app && "$DB_OWNER" != pride_owner ]]; then die "Database pride_bank exists but is owned by '$DB_OWNER'; refusing to modify a possible unrelated database."; fi
if [[ -n "$ROLE_EXISTS" && -z "$DB_OWNER" && ! -f "$STATE_DIR/managed" ]]; then die "PostgreSQL role pride_app exists but pride_bank database does not; refusing a possible naming collision."; fi
if [[ -n "$OWNER_ROLE_EXISTS" && -z "$DB_OWNER" && ! -f "$STATE_DIR/managed" ]]; then die "PostgreSQL role pride_owner exists but pride_bank database does not; refusing a possible naming collision."; fi
install -m 0600 /dev/null "$STATE_DIR/managed"

if [[ -z "$OWNER_ROLE_EXISTS" ]]; then
  as_postgres psql -v ON_ERROR_STOP=1 postgres -c "CREATE ROLE pride_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;" >/dev/null
  ok 'Created isolated PostgreSQL owner role pride_owner (NOLOGIN).'
fi

DB_PASSWORD=''
if [[ -f "$ENV_FILE" ]]; then
  DB_URL_EXISTING="$(python3 "$ENV_TOOL" get "$ENV_FILE" DATABASE_URL 2>/dev/null || true)"
  if [[ "$DB_URL_EXISTING" =~ ^postgresql://pride_app:([^@]+)@127\.0\.0\.1:5432/pride_bank$ ]]; then DB_PASSWORD="${BASH_REMATCH[1]}"; fi
fi
if [[ -z "$ROLE_EXISTS" ]]; then
  DB_PASSWORD="$(openssl rand -hex 24)"
  as_postgres psql -v ON_ERROR_STOP=1 postgres -c "CREATE ROLE pride_app LOGIN PASSWORD '$DB_PASSWORD' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;" >/dev/null
  ok 'Created isolated PostgreSQL login role pride_app.'
fi
if [[ -z "$DB_OWNER" ]]; then
  as_postgres createdb -O pride_owner pride_bank
  DB_OWNER=pride_owner
  ok 'Created isolated PostgreSQL database pride_bank owned by pride_owner.'
elif [[ "$DB_OWNER" == pride_app ]]; then
  as_postgres psql -v ON_ERROR_STOP=1 postgres -c "ALTER DATABASE pride_bank OWNER TO pride_owner;" >/dev/null
  DB_OWNER=pride_owner
  ok 'Migrated legacy Pride database ownership from login role pride_app to NOLOGIN role pride_owner.'
fi
as_postgres psql -v ON_ERROR_STOP=1 postgres -c "REVOKE ALL ON DATABASE pride_bank FROM PUBLIC; GRANT CONNECT ON DATABASE pride_bank TO pride_app;" >/dev/null
# Pride owns only the dedicated pride_bank database. Normalize only that database's
# public schema so migrations can create indexes/functions without relying on the
# PostgreSQL-version-specific default public-schema owner. Never touch other DBs.
PB_DB_CHECK="$(as_postgres psql -Atqc "select current_database() || ':' || pg_catalog.pg_get_userbyid((select datdba from pg_database where datname=current_database()))" pride_bank)"
[[ "$PB_DB_CHECK" == "pride_bank:pride_owner" ]] || die "Pride database safety check failed before schema ownership repair: $PB_DB_CHECK"
as_postgres psql -v ON_ERROR_STOP=1 pride_bank <<'SQL' >/dev/null
ALTER SCHEMA public OWNER TO pride_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM pride_app;
GRANT USAGE, CREATE ON SCHEMA public TO pride_owner;
GRANT USAGE ON SCHEMA public TO pride_app;
SQL
ok 'Verified Pride-only public schema ownership/privileges; no other database was changed.'
if [[ -z "$DB_PASSWORD" ]]; then
  # App-specific role/database are proven to be Pride-owned, but the old password
  # is unavailable. Rotate only this dedicated role; no shared role is touched.
  DB_PASSWORD="$(openssl rand -hex 24)"
  as_postgres psql -v ON_ERROR_STOP=1 postgres -c "ALTER ROLE pride_app PASSWORD '$DB_PASSWORD';" >/dev/null
  ok 'Rotated the dedicated pride_app database password because no Pride environment password was available.'
fi

SESSION_PEPPER="$(openssl rand -hex 32)"
if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  cat > "$ENV_FILE" <<ENV
NODE_ENV=production
PORT=4317
DATABASE_URL=postgresql://pride_app:${DB_PASSWORD}@127.0.0.1:5432/pride_bank
DATABASE_SSL=false
SESSION_PEPPER=${SESSION_PEPPER}
STRIPE_SECRET_KEY=CHANGE_ME
STRIPE_PUBLISHABLE_KEY=CHANGE_ME
STRIPE_WEBHOOK_SECRET=CHANGE_ME
STRIPE_WEBHOOK_ID=CHANGE_ME
STRIPE_MODE=test
STRIPE_EXPECTED_BUSINESS_NAME="WORKWORK.FUN LTD"
PUBLIC_BASE_URL=CHANGE_ME
IOS_BLOCKS_PURCHASE_RAIL=stripe
ENV
  chmod 600 "$ENV_FILE"
  ok 'Created /etc/pride-bank/server.env with generated database credentials and session pepper.'
else
  chmod 600 "$ENV_FILE"
  ok 'Preserved existing /etc/pride-bank/server.env without overwriting credentials.'
fi
[[ -r "$ENV_TOOL" ]] || die "Safe environment parser missing from staged release: $ENV_TOOL"
python3 "$ENV_TOOL" normalize "$ENV_FILE" >/dev/null
printf '%s\n' "$RELEASE_VERSION" | python3 "$ENV_TOOL" set-stdin "$ENV_FILE" PRIDE_RELEASE_VERSION
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok 'Validated and normalized Pride server environment as data (never executed as shell code).'

log "Staging isolated backend release v$RELEASE_VERSION"
rm -rf "$RELEASE_DIR.tmp"
mkdir -p "$RELEASE_DIR.tmp"
cp -a "$SOURCE_DIR"/. "$RELEASE_DIR.tmp"/
rm -rf "$RELEASE_DIR.tmp/node_modules"
cd "$RELEASE_DIR.tmp"
if [[ -f package-lock.json ]]; then npm ci --omit=dev --no-audit --no-fund; else npm install --omit=dev --no-audit --no-fund; fi
CURRENT_TARGET=""
[[ -L "$CURRENT_LINK" ]] && CURRENT_TARGET="$(readlink -f "$CURRENT_LINK" || true)"
if [[ -d "$RELEASE_DIR" && "$CURRENT_TARGET" == "$RELEASE_DIR" ]]; then
  rm -rf "$RELEASE_DIR.tmp"
  ok "Release v$RELEASE_VERSION is already the active backend source; reusing it for retry."
else
  rm -rf "$RELEASE_DIR"
  mv "$RELEASE_DIR.tmp" "$RELEASE_DIR"
fi
# Code is root-owned and writable only by root. The dedicated service group gets
# read/traverse access; unrelated host users get no access through this tree.
chown -R root:pride-bank "$RELEASE_DIR"
chmod -R g+rX,o-rwx "$RELEASE_DIR"

# Back up only Pride's database before any migration. Never dump or touch other DBs.
if as_postgres psql -Atqc "select to_regclass('public.users') is not null" pride_bank | grep -qx t; then
  DUMP="$BACKUP_DIR/postgres/pride_bank-pre-v${RELEASE_VERSION}-$(date +%Y%m%d%H%M%S).dump"
  as_postgres pg_dump -Fc pride_bank > "$DUMP"
  chmod 600 "$DUMP"
  ok "Backed up pride_bank to $DUMP"
fi

log 'Applying Pride-only PostgreSQL migrations as local postgres administrator'
as_postgres psql -v ON_ERROR_STOP=1 pride_bank -c "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()); ALTER TABLE schema_migrations OWNER TO pride_owner;" >/dev/null
for migration in "$RELEASE_DIR"/migrations/*.sql; do
  name="$(basename "$migration")"
  sql_name="${name//\'/\'\'}"
  applied="$(as_postgres psql -Atqc "select 1 from schema_migrations where name='${sql_name}'" pride_bank || true)"
  [[ "$applied" == 1 ]] && continue

  # Apply each migration and its bookkeeping row as one transaction. SQL is
  # streamed by root, so the postgres OS account never needs /opt traversal.
  if [[ "$name" == 002_ledger_security.sql ]]; then
    {
      printf 'BEGIN;\n'
      cat "$migration"
      printf "\nINSERT INTO schema_migrations(name) VALUES ('%s');\nCOMMIT;\n" "$sql_name"
    } | as_postgres psql -v ON_ERROR_STOP=1 pride_bank >/dev/null
  else
    {
      printf 'BEGIN;\nSET LOCAL ROLE pride_owner;\n'
      cat "$migration"
      printf "\nINSERT INTO schema_migrations(name) VALUES ('%s');\nCOMMIT;\n" "$sql_name"
    } | as_postgres psql -v ON_ERROR_STOP=1 pride_bank >/dev/null
  fi
  ok "Applied $name atomically"
done

# Reconcile only with an existing HTTPS nginx mapping that can be proven by an
# actual temporary file served from Pride's public root. A previous failed Pride
# deployment may have left our managed include in the site while its snippet was
# removed by an older rollback bug; repair that exact Pride-owned condition first
# so nginx -T can safely inspect the effective configuration.
PUBLIC_BASE_URL="$(python3 "$ENV_TOOL" get "$ENV_FILE" PUBLIC_BASE_URL 2>/dev/null || true)"
ORIGINAL_PUBLIC_BASE_URL="$PUBLIC_BASE_URL"
NGINX_SITE_FILE=''
NGINX_BACKUP=''
NGINX_CHANGED=0
SNIPPET_EXISTED=0
SNIPPET_BACKUP=''
SNIPPET_TOUCHED=0
SNIPPET_BASELINE_RECOVERED=0
is_https_base(){ [[ "$1" =~ ^https://[^/[:space:]]+(/[^[:space:]?#]*)?$ ]]; }
api_path_for_base(){
  python3 - "$1" <<'PYURL'
import sys
from urllib.parse import urlsplit
u=urlsplit(sys.argv[1])
p=(u.path or '').rstrip('/')
print((p if p else '') + '/api/')
PYURL
}
write_snippet_for_base(){
  local base="$1" api_path
  api_path="$(api_path_for_base "$base")"
  [[ "$api_path" == /api/ || "$api_path" == /*/api/ ]] || die "Refusing invalid Pride API path derived from $base"
  install -d -m 0755 "$(dirname "$SNIPPET")"
  sed "s|^location /api/ {|location $api_path {|" "$RELEASE_DIR/scripts/nginx-location.conf" > "$SNIPPET.tmp"
  install -m 0644 "$SNIPPET.tmp" "$SNIPPET"
  rm -f "$SNIPPET.tmp"
}

if command -v nginx >/dev/null 2>&1; then
  # Recover only our exact managed include if an older failed release removed the
  # snippet. This changes no server block and no unrelated nginx file.
  if [[ ! -f "$SNIPPET" ]]; then
    PRIDE_INCLUDE_COUNT="$( { grep -RFl -- "include $SNIPPET;" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true; } | wc -l | tr -d '[:space:]')"
    if [[ "$PRIDE_INCLUDE_COUNT" != 0 ]]; then
      RECOVERY_BASE="$PUBLIC_BASE_URL"
      if ! is_https_base "$RECOVERY_BASE"; then RECOVERY_BASE="$PREFERRED_PUBLIC_URL"; fi
      is_https_base "$RECOVERY_BASE" || die "A Pride-managed nginx include exists but its snippet is missing and no proven HTTPS Pride URL is available to reconstruct it."
      write_snippet_for_base "$RECOVERY_BASE"
      if nginx -t >/dev/null 2>&1; then
        SNIPPET_BASELINE_RECOVERED=1
        ok 'Recovered missing Pride nginx snippet left by an older failed release; nginx configuration is valid again.'
      else
        rm -f "$SNIPPET"
        die 'A Pride-managed nginx include references a missing snippet, but reconstructing the snippet did not produce a valid nginx configuration.'
      fi
    fi
  fi

  # Always re-prove the mapping. A stored URL is a preference, never authority.
  DISCOVERY_ARGS=(--root "$PUBLIC_ROOT")
  if is_https_base "$PUBLIC_BASE_URL"; then
    DISCOVERY_ARGS+=(--preferred-base-url "$PUBLIC_BASE_URL")
    printf 'Stored canonical Pride URL: %s\n' "$PUBLIC_BASE_URL"
  elif is_https_base "$PREFERRED_PUBLIC_URL"; then
    DISCOVERY_ARGS+=(--preferred-base-url "$PREFERRED_PUBLIC_URL")
    printf 'Preferred canonical Pride URL: %s\n' "$PREFERRED_PUBLIC_URL"
  fi
  set +e
  DISCOVERY="$(python3 "$RELEASE_DIR/scripts/discover_nginx.py" "${DISCOVERY_ARGS[@]}" 2>&1)"
  DISCOVERY_RC=$?
  set -e
  if (( DISCOVERY_RC == 0 )); then
    printf '%s\n' "$DISCOVERY"
    NGINX_SITE_FILE="$(printf '%s\n' "$DISCOVERY" | sed -n 's/^SITE_FILE=//p' | tail -n1)"
    SERVER_NAME="$(printf '%s\n' "$DISCOVERY" | sed -n 's/^SERVER_NAME=//p' | tail -n1)"
    BASE_PATH="$(printf '%s\n' "$DISCOVERY" | sed -n 's/^BASE_PATH=//p' | tail -n1)"
    DISCOVERED="$(printf '%s\n' "$DISCOVERY" | sed -n 's/^PUBLIC_BASE_URL=//p' | tail -n1)"
    [[ -n "$NGINX_SITE_FILE" && -f "$NGINX_SITE_FILE" ]] || die 'nginx discovery returned an invalid source config file.'
    [[ "$SERVER_NAME" =~ ^[A-Za-z0-9.-]+$ ]] || die 'nginx discovery returned an invalid server_name.'
    [[ "$BASE_PATH" == /* ]] || die 'nginx discovery returned an invalid public base path.'
    is_https_base "$DISCOVERED" || die 'nginx discovery returned an invalid HTTPS public URL.'

    install -d -m 0755 "$(dirname "$SNIPPET")"
    if [[ -f "$SNIPPET" ]]; then
      SNIPPET_EXISTED=1
      SNIPPET_BACKUP="$BACKUP_DIR/nginx/pride-bank-api.conf.$(date +%Y%m%d%H%M%S).bak"
      cp -a "$SNIPPET" "$SNIPPET_BACKUP"
    fi
    write_snippet_for_base "$DISCOVERED"
    SNIPPET_TOUCHED=1

    set +e
    NGINX_RESULT="$(python3 "$RELEASE_DIR/scripts/configure_nginx.py" --site "$NGINX_SITE_FILE" --server-name "$SERVER_NAME" --snippet "$SNIPPET" --backup-dir "$BACKUP_DIR/nginx" 2>&1)"
    NGINX_RC=$?
    set -e
    if (( NGINX_RC == 0 )); then
      printf '%s\n' "$NGINX_RESULT"
      NGINX_BACKUP="$(printf '%s\n' "$NGINX_RESULT" | sed -n 's/^BACKUP=//p' | tail -n1)"
      [[ -n "$NGINX_BACKUP" ]] && NGINX_CHANGED=1
      if nginx -t; then
        if (( NGINX_CHANGED || SNIPPET_TOUCHED )); then
          systemctl reload nginx || die 'nginx reload failed after Pride-only API reconciliation.'
        fi
        printf '%s\n' "$DISCOVERED" | python3 "$ENV_TOOL" set-stdin "$ENV_FILE" PUBLIC_BASE_URL
        PUBLIC_BASE_URL="$DISCOVERED"
        ok "Verified Pride API nginx route on the single HTTPS mapping proven by a live file probe: $DISCOVERED (reload only)."
      else
        [[ -n "$NGINX_BACKUP" ]] && cp -a "$NGINX_BACKUP" "$NGINX_SITE_FILE"
        if (( SNIPPET_EXISTED )) && [[ -n "$SNIPPET_BACKUP" ]]; then cp -a "$SNIPPET_BACKUP" "$SNIPPET"; elif (( ! SNIPPET_BASELINE_RECOVERED )); then rm -f "$SNIPPET"; fi
        nginx -t || true
        die 'nginx validation failed; Pride-only files were restored where possible.'
      fi
    else
      warn "$NGINX_RESULT"
      warn 'The proven nginx source block could not be modified safely; no persistent public URL was recorded.'
      MANUAL=1
    fi
  else
    warn "$DISCOVERY"
    warn 'Could not prove exactly one HTTPS mapping for the Pride public root. No nginx server block was modified.'
    MANUAL=1
  fi
else
  warn 'nginx is not installed. Pride will not install/take over a web server on a shared host without an existing HTTPS site.'
  MANUAL=1
fi

rollback_nginx_mapping(){
  # Roll back only files this invocation actually changed. Never remove a
  # pre-existing/recovered Pride snippet merely because a later app health check
  # failed; doing so can make the host's nginx configuration invalid on disk.
  if (( NGINX_CHANGED )) && [[ -n "$NGINX_BACKUP" && -n "$NGINX_SITE_FILE" ]]; then
    cp -a "$NGINX_BACKUP" "$NGINX_SITE_FILE"
  fi
  if (( SNIPPET_TOUCHED )); then
    if (( SNIPPET_EXISTED )) && [[ -n "$SNIPPET_BACKUP" ]]; then
      cp -a "$SNIPPET_BACKUP" "$SNIPPET"
    elif (( ! SNIPPET_BASELINE_RECOVERED )); then
      rm -f "$SNIPPET"
    fi
  fi
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
  else
    warn 'Rollback left nginx validation failing; Pride will not reload an invalid configuration.'
  fi
  if [[ -n "$ORIGINAL_PUBLIC_BASE_URL" ]]; then
    printf '%s\n' "$ORIGINAL_PUBLIC_BASE_URL" | python3 "$ENV_TOOL" set-stdin "$ENV_FILE" PUBLIC_BASE_URL
  else
    printf 'CHANGE_ME\n' | python3 "$ENV_TOOL" set-stdin "$ENV_FILE" PUBLIC_BASE_URL
  fi
}

# Human secrets are the only intentionally non-generated values.
STRIPE_SECRET="$(python3 "$ENV_TOOL" get "$ENV_FILE" STRIPE_SECRET_KEY 2>/dev/null || true)"
STRIPE_PUB="$(python3 "$ENV_TOOL" get "$ENV_FILE" STRIPE_PUBLISHABLE_KEY 2>/dev/null || true)"
WEBHOOK_SECRET="$(python3 "$ENV_TOOL" get "$ENV_FILE" STRIPE_WEBHOOK_SECRET 2>/dev/null || true)"
WEBHOOK_ID="$(python3 "$ENV_TOOL" get "$ENV_FILE" STRIPE_WEBHOOK_ID 2>/dev/null || true)"
if [[ ! "$STRIPE_SECRET" =~ ^sk_(test|live)_ ]] || [[ ! "$STRIPE_PUB" =~ ^pk_(test|live)_ ]]; then
  warn 'Stripe credentials are not yet configured. The foreground watcher can collect these once with hidden secret input.'
  NEED_STRIPE_KEYS=1
  MANUAL=1
fi
if ! is_https_base "$PUBLIC_BASE_URL"; then
  warn 'PUBLIC_BASE_URL is not an HTTPS origin yet. Pride cannot safely expose account/payment APIs without HTTPS.'
  NEED_HTTPS_MAPPING=1
  MANUAL=1
fi

if (( MANUAL )); then
  printf '\nPRIDE_BOOTSTRAP_STATUS=ACTION_REQUIRED\n'
  printf 'PRIDE_ENV_FILE=%s\n' "$ENV_FILE"
  printf 'NEED_STRIPE_KEYS=%s\n' "$NEED_STRIPE_KEYS"
  printf 'NEED_HTTPS_MAPPING=%s\n' "$NEED_HTTPS_MAPPING"
  exit 78
fi

# Create or reconcile the Pride Stripe webhook after one exact HTTPS mapping is
# proven. Store both endpoint id and signing secret so later path/host changes can
# update the same endpoint without losing the signing secret.
python3 "$ENV_TOOL" validate "$ENV_FILE" >/dev/null
set +e
STRIPE_RESULT="$(python3 "$ENV_TOOL" exec "$ENV_FILE" -- node "$RELEASE_DIR/scripts/configure-stripe.js" 2>&1)"
STRIPE_RC=$?
set -e
if (( STRIPE_RC == 0 )); then
  NEW_ACCOUNT_ID="$(printf '%s\n' "$STRIPE_RESULT" | sed -n 's/^STRIPE_ACCOUNT_ID=//p' | tail -n1)"
  NEW_WHSEC="$(printf '%s\n' "$STRIPE_RESULT" | sed -n 's/^STRIPE_WEBHOOK_SECRET=//p' | tail -n1)"
  NEW_WEBHOOK_ID="$(printf '%s\n' "$STRIPE_RESULT" | sed -n 's/^STRIPE_WEBHOOK_ID=//p' | tail -n1)"
  [[ "$NEW_ACCOUNT_ID" =~ ^acct_ ]] || die 'Stripe setup succeeded without a usable account id.'
  [[ "$NEW_WHSEC" =~ ^whsec_ ]] || die 'Stripe webhook setup succeeded without a usable signing secret.'
  [[ "$NEW_WEBHOOK_ID" =~ ^we_ ]] || die 'Stripe webhook setup succeeded without a usable endpoint id.'
  printf 'STRIPE_ACCOUNT_ID=%s\nSTRIPE_WEBHOOK_SECRET=%s\nSTRIPE_WEBHOOK_ID=%s\n' "$NEW_ACCOUNT_ID" "$NEW_WHSEC" "$NEW_WEBHOOK_ID" | python3 "$ENV_TOOL" set-many-stdin "$ENV_FILE"
  python3 "$ENV_TOOL" validate "$ENV_FILE" >/dev/null
  WEBHOOK_SECRET="$NEW_WHSEC"
  WEBHOOK_ID="$NEW_WEBHOOK_ID"
  ok 'Stripe webhook endpoint is configured and its signing secret is stored root-only.'
elif (( STRIPE_RC == 2 )); then
  warn "$STRIPE_RESULT"
  rollback_nginx_mapping
  die 'A Stripe webhook exists but its signing secret is not available locally. The nginx change was rolled back; no endpoint secret was guessed.'
else
  printf '%s\n' "$STRIPE_RESULT" >&2
  rollback_nginx_mapping
  die 'Stripe webhook provisioning failed; nginx mapping was rolled back when changed by this release.'
fi

# Install/update only Pride's service unit, with backup if it already exists.
# Prove the runtime user can traverse/read the exact staged application before
# changing the current symlink or touching systemd.
if ! runuser -u pride-bank -- test -r "$RELEASE_DIR/src/index.js"; then
  die "Dedicated pride-bank service user cannot read staged release $RELEASE_DIR/src/index.js; refusing activation."
fi
ok 'Dedicated service user can read/traverse the staged backend release.'

log 'Activating isolated Pride backend release'
if [[ -f "$SERVICE_FILE" ]]; then cp -a "$SERVICE_FILE" "$BACKUP_DIR/pride-blocks.service.$(date +%Y%m%d%H%M%S).bak"; fi
install -m 0644 "$RELEASE_DIR/scripts/pride-blocks.service" "$SERVICE_FILE"
PREVIOUS=''
[[ -L "$CURRENT_LINK" ]] && PREVIOUS="$(readlink -f "$CURRENT_LINK" || true)"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK.new"
mv -Tf "$CURRENT_LINK.new" "$CURRENT_LINK"
chown -h root:root "$CURRENT_LINK"
systemctl daemon-reload
systemctl enable pride-blocks.service >/dev/null
if ! systemctl restart pride-blocks.service; then
  [[ -n "$PREVIOUS" ]] && ln -sfn "$PREVIOUS" "$CURRENT_LINK"
  systemctl restart pride-blocks.service || true
  die 'Pride service failed to restart; previous release symlink was restored.'
fi
sleep 1
if ! curl --fail --silent http://127.0.0.1:4317/healthz >/dev/null; then
  journalctl -u pride-blocks.service -n 100 --no-pager >&2 || true
  if [[ -n "$PREVIOUS" ]]; then ln -sfn "$PREVIOUS" "$CURRENT_LINK"; systemctl restart pride-blocks.service || true; fi
  rollback_nginx_mapping
  die 'Pride API health check failed; previous release and nginx mapping were restored when available.'
fi
PUBLIC_HEALTH_URL="${PUBLIC_BASE_URL%/}/api/healthz"
if ! curl --fail --silent --show-error --max-time 10 "$PUBLIC_HEALTH_URL" >/dev/null; then
  journalctl -u pride-blocks.service -n 100 --no-pager >&2 || true
  if [[ -n "$PREVIOUS" ]]; then ln -sfn "$PREVIOUS" "$CURRENT_LINK"; systemctl restart pride-blocks.service || true; fi
  rollback_nginx_mapping
  die "Pride API is healthy locally but not through the proven HTTPS route $PUBLIC_HEALTH_URL; nginx mapping was rolled back."
fi
ok "Pride API HTTPS route verified: $PUBLIC_HEALTH_URL"
chown -R pride-bank:pride-bank "$STATE_DIR"
chmod 750 "$STATE_DIR"
ok 'Pride API is healthy on 127.0.0.1:4317.'
printf 'PRIDE_BOOTSTRAP_STATUS=READY\n'
printf 'PUBLIC_BASE_URL=%s\n' "$PUBLIC_BASE_URL"
printf 'PRIDE_API_BASE_URL=%s/api/\n' "${PUBLIC_BASE_URL%/}"
