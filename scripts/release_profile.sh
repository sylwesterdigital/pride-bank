#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
PB_RELEASE_PROFILE="${PB_RELEASE_PROFILE:-$HOME/.config/workwork/pride-bank-release.env}"
RANTLIST_RELEASE_PROFILE="${RANTLIST_RELEASE_PROFILE:-$HOME/.config/workwork/rantlist-release.env}"
RANTLIST_PROFILE_LOADER="${RANTLIST_PROFILE_LOADER:-$HOME/Documents/works/rantlist-client/scripts/release_profile.sh}"
SHAR_RELEASE_PROFILE="${SHAR_RELEASE_PROFILE:-$HOME/.config/workwork/shar-release.env}"
PB_REMOTE_DIR_DEFAULT='/var/www/mojoworks/labs/bank'
pb_write_profile(){ mkdir -p "$(dirname "$PB_RELEASE_PROFILE")"; umask 077; { printf 'PB_REMOTE_USER=%q\n' "$PB_REMOTE_USER"; printf 'PB_REMOTE_HOST=%q\n' "$PB_REMOTE_HOST"; printf 'PB_REMOTE_PORT=%q\n' "$PB_REMOTE_PORT"; printf 'PB_REMOTE_DIR=%q\n' "$PB_REMOTE_DIR"; printf 'PB_REMOTE_OWNER=%q\n' "$PB_REMOTE_OWNER"; printf 'PB_REMOTE_CHMOD=%q\n' "$PB_REMOTE_CHMOD"; printf 'PB_REMOTE_URL=%q\n' "${PB_REMOTE_URL:-}"; printf 'PB_API_BASE_URL=%q\n' "${PB_API_BASE_URL:-}"; } > "$PB_RELEASE_PROFILE"; chmod 600 "$PB_RELEASE_PROFILE"; }
pb_import_existing_profile(){
  if [[ ! -f "$RANTLIST_RELEASE_PROFILE" && -f "$RANTLIST_PROFILE_LOADER" ]]; then source "$RANTLIST_PROFILE_LOADER"; if typeset -f rantlist_load_release_profile >/dev/null 2>&1; then rantlist_load_release_profile >/dev/null || true; fi; fi
  if [[ -f "$RANTLIST_RELEASE_PROFILE" ]]; then source "$RANTLIST_RELEASE_PROFILE"; : "${RANTLIST_REMOTE_USER:?RANTLIST_REMOTE_USER missing}"; : "${RANTLIST_REMOTE_HOST:?RANTLIST_REMOTE_HOST missing}"; : "${RANTLIST_REMOTE_PORT:?RANTLIST_REMOTE_PORT missing}"; PB_REMOTE_USER="$RANTLIST_REMOTE_USER"; PB_REMOTE_HOST="$RANTLIST_REMOTE_HOST"; PB_REMOTE_PORT="$RANTLIST_REMOTE_PORT"; PB_REMOTE_DIR="$PB_REMOTE_DIR_DEFAULT"; PB_REMOTE_OWNER="${RANTLIST_REMOTE_OWNER:-www-data:www-data}"; PB_REMOTE_CHMOD="${RANTLIST_REMOTE_CHMOD:-Du=rwx,Dgo=rx,Fu=rw,Fgo=r}"; PB_REMOTE_URL="${RANTLIST_REMOTE_URL:-}"; PB_API_BASE_URL="${RANTLIST_API_BASE_URL:-${PB_REMOTE_URL:+${PB_REMOTE_URL%/}/api/}}"; pb_write_profile; printf 'Imported Pride Bank deployment profile from the existing Rantlist release profile: %s\n' "$PB_RELEASE_PROFILE"; return 0; fi
  if [[ -f "$SHAR_RELEASE_PROFILE" ]]; then source "$SHAR_RELEASE_PROFILE"; : "${SHAR_REMOTE_USER:?SHAR_REMOTE_USER missing}"; : "${SHAR_REMOTE_HOST:?SHAR_REMOTE_HOST missing}"; : "${SHAR_REMOTE_PORT:?SHAR_REMOTE_PORT missing}"; PB_REMOTE_USER="$SHAR_REMOTE_USER"; PB_REMOTE_HOST="$SHAR_REMOTE_HOST"; PB_REMOTE_PORT="$SHAR_REMOTE_PORT"; PB_REMOTE_DIR="$PB_REMOTE_DIR_DEFAULT"; PB_REMOTE_OWNER="${SHAR_REMOTE_OWNER:-www-data:www-data}"; PB_REMOTE_CHMOD="${SHAR_REMOTE_CHMOD:-Du=rwx,Dgo=rx,Fu=rw,Fgo=r}"; PB_REMOTE_URL="${SHAR_REMOTE_URL:-}"; PB_API_BASE_URL="${SHAR_API_BASE_URL:-${PB_REMOTE_URL:+${PB_REMOTE_URL%/}/api/}}"; pb_write_profile; printf 'Imported Pride Bank deployment profile from the existing Shar release profile: %s\n' "$PB_RELEASE_PROFILE"; return 0; fi
  return 1
}
pb_load_release_profile(){
  if [[ ! -f "$PB_RELEASE_PROFILE" ]]; then pb_import_existing_profile || { printf 'ERROR: Pride Bank deployment profile is missing and no Rantlist/Shar profile could be imported.\n' >&2; return 1; }; fi
  source "$PB_RELEASE_PROFILE"; : "${PB_REMOTE_USER:?PB_REMOTE_USER missing}"; : "${PB_REMOTE_HOST:?PB_REMOTE_HOST missing}"; : "${PB_REMOTE_PORT:?PB_REMOTE_PORT missing}"; PB_REMOTE_DIR="${PB_REMOTE_DIR:-$PB_REMOTE_DIR_DEFAULT}"; PB_REMOTE_OWNER="${PB_REMOTE_OWNER:-www-data:www-data}"; PB_REMOTE_CHMOD="${PB_REMOTE_CHMOD:-Du=rwx,Dgo=rx,Fu=rw,Fgo=r}"; PB_REMOTE_URL="${PB_REMOTE_URL:-}"; PB_API_BASE_URL="${PB_API_BASE_URL:-${PB_REMOTE_URL:+${PB_REMOTE_URL%/}/api/}}"
  [[ "$PB_REMOTE_DIR" == "$PB_REMOTE_DIR_DEFAULT" ]] || { printf 'ERROR: refusing unexpected Pride Bank remote path: %s\n' "$PB_REMOTE_DIR" >&2; return 1; }
}
