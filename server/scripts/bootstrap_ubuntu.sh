#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
VERSION="${PB_VERSION:?PB_VERSION missing}"
SOURCE_DIR="${PB_SOURCE_DIR:?PB_SOURCE_DIR missing}"
PUBLIC_ROOT="${PB_PUBLIC_ROOT:-/var/www/mojoworks/labs/bank}"
APP_ROOT=/opt/pride-bank
RELEASE_DIR="$APP_ROOT/releases/$VERSION"
CURRENT_LINK="$APP_ROOT/current"
ETC_DIR=/etc/pride-bank
STATE_DIR=/var/lib/pride-bank
BACKUP_DIR=/var/backups/pride-bank
ENV_FILE="$ETC_DIR/server.env"
SERVICE_FILE=/etc/systemd/system/pride-blocks.service
SNIPPET=/etc/nginx/snippets/pride-bank-api.conf
MANUAL=0
NEED_STRIPE_KEYS=0
NEED_HTTPS_MAPPING=0

log(){ printf '\n==> %s\n' "$*"; }
ok(){ printf '✓ %s\n' "$*"; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then die "bootstrap_ubuntu.sh must run as root (the release script uses root or sudo -n)."; fi
[[ -r /etc/os-release ]] || die '/etc/os-release missing'
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "Refusing automatic host bootstrap on non-Ubuntu system: ${PRETTY_NAME:-unknown}"
command -v systemctl >/dev/null || die 'systemd is required'
mkdir -p "$ETC_DIR" "$STATE_DIR" "$BACKUP_DIR/postgres" "$BACKUP_DIR/nginx" "$APP_ROOT/releases"
chmod 750 "$ETC_DIR" "$STATE_DIR" "$BACKUP_DIR" "$BACKUP_DIR/postgres" "$BACKUP_DIR/nginx" "$APP_ROOT" "$APP_ROOT/releases"

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
if ! runuser -u postgres -- psql -Atqc 'select current_database()' postgres >/dev/null 2>&1; then
  if (( PG_NEW )); then
    systemctl enable --now postgresql
  else
    die 'PostgreSQL is installed but the existing local cluster is not accepting local postgres connections. Refusing to start/change an existing cluster automatically.'
  fi
fi
runuser -u postgres -- psql -Atqc 'select version()' postgres >/dev/null || die 'Local PostgreSQL safety check failed'
ok 'Existing/local PostgreSQL cluster is healthy; no global PostgreSQL configuration was changed.'

if ! getent passwd pride-bank >/dev/null; then
  useradd --system --home "$STATE_DIR" --shell /usr/sbin/nologin pride-bank
  ok 'Created dedicated pride-bank service user.'
fi

# Detect collisions before touching app-specific DB resources. Pride uses a NOLOGIN
# owner role so the network-facing API role never owns ledger tables/functions.
ROLE_EXISTS="$(runuser -u postgres -- psql -Atqc "select 1 from pg_roles where rolname='pride_app'" postgres || true)"
OWNER_ROLE_EXISTS="$(runuser -u postgres -- psql -Atqc "select 1 from pg_roles where rolname='pride_owner'" postgres || true)"
DB_OWNER="$(runuser -u postgres -- psql -Atqc "select pg_catalog.pg_get_userbyid(datdba) from pg_database where datname='pride_bank'" postgres || true)"
if [[ -n "$DB_OWNER" && "$DB_OWNER" != pride_app && "$DB_OWNER" != pride_owner ]]; then die "Database pride_bank exists but is owned by '$DB_OWNER'; refusing to modify a possible unrelated database."; fi
if [[ -n "$ROLE_EXISTS" && -z "$DB_OWNER" && ! -f "$STATE_DIR/managed" ]]; then die "PostgreSQL role pride_app exists but pride_bank database does not; refusing a possible naming collision."; fi
if [[ -n "$OWNER_ROLE_EXISTS" && -z "$DB_OWNER" && ! -f "$STATE_DIR/managed" ]]; then die "PostgreSQL role pride_owner exists but pride_bank database does not; refusing a possible naming collision."; fi
install -m 0600 /dev/null "$STATE_DIR/managed"

if [[ -z "$OWNER_ROLE_EXISTS" ]]; then
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 postgres -c "CREATE ROLE pride_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;" >/dev/null
  ok 'Created isolated PostgreSQL owner role pride_owner (NOLOGIN).'
fi

DB_PASSWORD=''
if [[ -f "$ENV_FILE" ]]; then
  DB_URL_EXISTING="$(grep -E '^DATABASE_URL=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ "$DB_URL_EXISTING" =~ ^postgresql://pride_app:([^@]+)@127\.0\.0\.1:5432/pride_bank$ ]]; then DB_PASSWORD="${BASH_REMATCH[1]}"; fi
fi
if [[ -z "$ROLE_EXISTS" ]]; then
  DB_PASSWORD="$(openssl rand -hex 24)"
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 postgres -c "CREATE ROLE pride_app LOGIN PASSWORD '$DB_PASSWORD' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;" >/dev/null
  ok 'Created isolated PostgreSQL login role pride_app.'
fi
if [[ -z "$DB_OWNER" ]]; then
  runuser -u postgres -- createdb -O pride_owner pride_bank
  DB_OWNER=pride_owner
  ok 'Created isolated PostgreSQL database pride_bank owned by pride_owner.'
elif [[ "$DB_OWNER" == pride_app ]]; then
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 postgres -c "ALTER DATABASE pride_bank OWNER TO pride_owner;" >/dev/null
  DB_OWNER=pride_owner
  ok 'Migrated legacy Pride database ownership from login role pride_app to NOLOGIN role pride_owner.'
fi
runuser -u postgres -- psql -v ON_ERROR_STOP=1 postgres -c "REVOKE ALL ON DATABASE pride_bank FROM PUBLIC; GRANT CONNECT ON DATABASE pride_bank TO pride_app;" >/dev/null
if [[ -z "$DB_PASSWORD" ]]; then
  # App-specific role/database are proven to be Pride-owned, but the old password
  # is unavailable. Rotate only this dedicated role; no shared role is touched.
  DB_PASSWORD="$(openssl rand -hex 24)"
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 postgres -c "ALTER ROLE pride_app PASSWORD '$DB_PASSWORD';" >/dev/null
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
STRIPE_MODE=test
STRIPE_EXPECTED_BUSINESS_NAME=WORKWORK.FUN LTD
PUBLIC_BASE_URL=CHANGE_ME
IOS_BLOCKS_PURCHASE_RAIL=stripe
ENV
  chmod 600 "$ENV_FILE"
  ok 'Created /etc/pride-bank/server.env with generated database credentials and session pepper.'
else
  chmod 600 "$ENV_FILE"
  ok 'Preserved existing /etc/pride-bank/server.env without overwriting credentials.'
fi

log "Staging isolated backend release v$VERSION"
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
  ok "Release v$VERSION is already the active backend source; reusing it for retry."
else
  rm -rf "$RELEASE_DIR"
  mv "$RELEASE_DIR.tmp" "$RELEASE_DIR"
  chown -R root:root "$RELEASE_DIR"
  chmod -R a+rX "$RELEASE_DIR"
fi

# Back up only Pride's database before any migration. Never dump or touch other DBs.
if runuser -u postgres -- psql -Atqc "select to_regclass('public.users') is not null" pride_bank | grep -qx t; then
  DUMP="$BACKUP_DIR/postgres/pride_bank-pre-v${VERSION}-$(date +%Y%m%d%H%M%S).dump"
  runuser -u postgres -- pg_dump -Fc pride_bank -f "$DUMP"
  chmod 600 "$DUMP"
  ok "Backed up pride_bank to $DUMP"
fi

log 'Applying Pride-only PostgreSQL migrations as local postgres administrator'
runuser -u postgres -- psql -v ON_ERROR_STOP=1 pride_bank -c "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()); ALTER TABLE schema_migrations OWNER TO pride_owner;" >/dev/null
for migration in "$RELEASE_DIR"/migrations/*.sql; do
  name="$(basename "$migration")"
  applied="$(runuser -u postgres -- psql -Atqc "select 1 from schema_migrations where name='${name//\'/\'\'}'" pride_bank || true)"
  [[ "$applied" == 1 ]] && continue
  if [[ "$name" == 002_ledger_security.sql ]]; then
    # This migration intentionally needs postgres authority once to normalize
    # ownership from the legacy v0.3.1 layout before locking the API role down.
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 pride_bank -f "$migration" >/dev/null
  else
    { printf 'SET ROLE pride_owner;\n'; cat "$migration"; } | runuser -u postgres -- psql -v ON_ERROR_STOP=1 pride_bank >/dev/null
  fi
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 pride_bank -c "insert into schema_migrations(name) values ('${name//\'/\'\'}')" >/dev/null
  ok "Applied $name"
done

# Ensure existing web server integration is modified only when unambiguous.
PUBLIC_BASE_URL="$(grep -E '^PUBLIC_BASE_URL=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
if [[ ! "$PUBLIC_BASE_URL" =~ ^https://[^/[:space:]]+$ ]]; then
  if command -v nginx >/dev/null 2>&1; then
    mapfile -t SITE_FILES < <(grep -RIl --exclude='*.bak' -F "$PUBLIC_ROOT" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | xargs -r -n1 readlink -f | sort -u)
    if (( ${#SITE_FILES[@]} == 1 )); then
      install -D -m 0644 "$RELEASE_DIR/scripts/nginx-location.conf" "$SNIPPET"
      set +e
      NGINX_RESULT="$(python3 "$RELEASE_DIR/scripts/configure_nginx.py" --site "${SITE_FILES[0]}" --root "$PUBLIC_ROOT" --backup-dir "$BACKUP_DIR/nginx" 2>&1)"
      NGINX_RC=$?
      set -e
      if (( NGINX_RC == 0 )); then
        printf '%s\n' "$NGINX_RESULT"
        DISCOVERED="$(printf '%s\n' "$NGINX_RESULT" | sed -n 's/^PUBLIC_BASE_URL=//p' | tail -n1)"
        BACKUP="$(printf '%s\n' "$NGINX_RESULT" | sed -n 's/^BACKUP=//p' | tail -n1)"
        if nginx -t; then
          if systemctl reload nginx; then
            sed -i "s|^PUBLIC_BASE_URL=.*$|PUBLIC_BASE_URL=$DISCOVERED|" "$ENV_FILE"
            PUBLIC_BASE_URL="$DISCOVERED"
            ok "Added Pride /api/ include to the single HTTPS nginx site serving $PUBLIC_ROOT and reloaded nginx (no restart)."
          else
            [[ -n "$BACKUP" ]] && cp -a "$BACKUP" "${SITE_FILES[0]}"
            nginx -t && systemctl reload nginx || true
            die 'nginx reload failed; original site file was restored.'
          fi
        else
          [[ -n "$BACKUP" ]] && cp -a "$BACKUP" "${SITE_FILES[0]}"
          nginx -t || true
          die 'nginx validation failed; original site file was restored.'
        fi
      else
        warn "$NGINX_RESULT"
        warn 'Existing nginx configuration was left untouched because Pride could not identify one safe HTTPS server block.'
        MANUAL=1
      fi
    else
      warn "Found ${#SITE_FILES[@]} nginx config files referencing $PUBLIC_ROOT; expected exactly one. No nginx files were modified."
      MANUAL=1
    fi
  else
    warn 'nginx is not installed. Pride will not install/take over a web server on a shared host without an unambiguous HTTPS site.'
    MANUAL=1
  fi
fi

# Human secrets are the only intentionally non-generated values.
STRIPE_SECRET="$(grep -E '^STRIPE_SECRET_KEY=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
STRIPE_PUB="$(grep -E '^STRIPE_PUBLISHABLE_KEY=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
WEBHOOK_SECRET="$(grep -E '^STRIPE_WEBHOOK_SECRET=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
if [[ ! "$STRIPE_SECRET" =~ ^sk_(test|live)_ ]] || [[ ! "$STRIPE_PUB" =~ ^pk_(test|live)_ ]]; then
  warn 'Stripe credentials are not yet configured. The foreground watcher can collect these once with hidden secret input.'
  NEED_STRIPE_KEYS=1
  MANUAL=1
fi
if [[ ! "$PUBLIC_BASE_URL" =~ ^https:// ]]; then
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

# Once the secret key + HTTPS origin exist, create the Stripe webhook automatically
# if this Pride install does not already have a stored webhook secret.
if [[ ! "$WEBHOOK_SECRET" =~ ^whsec_ ]]; then
  set -a; . "$ENV_FILE"; set +a
  set +e
  STRIPE_RESULT="$(node "$RELEASE_DIR/scripts/configure-stripe.js" 2>&1)"
  STRIPE_RC=$?
  set -e
  if (( STRIPE_RC == 0 )); then
    NEW_WHSEC="$(printf '%s\n' "$STRIPE_RESULT" | sed -n 's/^STRIPE_WEBHOOK_SECRET=//p' | tail -n1)"
    [[ "$NEW_WHSEC" =~ ^whsec_ ]] || die 'Stripe webhook creation succeeded without returning a webhook secret.'
    sed -i "s|^STRIPE_WEBHOOK_SECRET=.*$|STRIPE_WEBHOOK_SECRET=$NEW_WHSEC|" "$ENV_FILE"
    WEBHOOK_SECRET="$NEW_WHSEC"
    ok 'Created and stored the Stripe webhook endpoint secret automatically.'
  elif (( STRIPE_RC == 2 )); then
    warn "$STRIPE_RESULT"
    die 'A Stripe webhook already exists for this URL but its signing secret is not stored locally. Create a new endpoint or place its whsec_ secret in /etc/pride-bank/server.env.'
  else
    printf '%s\n' "$STRIPE_RESULT" >&2
    die 'Stripe webhook provisioning failed.'
  fi
fi

# Install/update only Pride's service unit, with backup if it already exists.
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
  die 'Pride API health check failed; previous release was restored when available.'
fi
chown -R pride-bank:pride-bank "$STATE_DIR"
chmod 750 "$STATE_DIR"
ok 'Pride API is healthy on 127.0.0.1:4317.'
printf 'PRIDE_BOOTSTRAP_STATUS=READY\n'
printf 'PUBLIC_BASE_URL=%s\n' "$PUBLIC_BASE_URL"
printf 'PRIDE_API_BASE_URL=%s/api/\n' "${PUBLIC_BASE_URL%/}"
