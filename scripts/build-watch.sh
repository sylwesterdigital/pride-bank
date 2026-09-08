#!/bin/zsh
# Foreground release watcher for Pride Bank, modelled on the supplied Shar watcher.
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/terminal_style.sh"
REPO_DIR="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
WATCH_DIR="${WATCH_DIR:-$REPO_DIR/archive}"
ZIP_PATTERN="pride-bank-v*.zip"
STATE_DIR="${STATE_DIR:-$REPO_DIR/.watch-state}"
STATE_FILE="$STATE_DIR/processed-signatures"
DEPLOYED_VERSION_FILE="$STATE_DIR/deployed-version"
LOCK_DIR="${TMPDIR:-/tmp}/pride-bank-watch.lock"
POLL_SECONDS="${POLL_SECONDS:-5}"
STABLE_SECONDS="${STABLE_SECONDS:-3}"
ZSH_BIN="${ZSH_BIN:-/bin/zsh}"
mkdir -p "$WATCH_DIR" "$STATE_DIR"
cleanup(){ rm -rf "$LOCK_DIR"; }
trap 'cleanup; echo; pb_warn "Pride Bank watcher stopped."; exit 130' INT TERM
trap cleanup EXIT
if ! mkdir "$LOCK_DIR" 2>/dev/null; then pb_error "Pride Bank watcher is already running."; exit 1; fi
log(){ printf '%b[%s]%b %s\n' "$PB_C_MUTED" "$(date '+%H:%M:%S')" "$PB_C_RESET" "$*"; }
valid_version(){ [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
version_gt(){ python3 - "$1" "$2" <<'PY'
import sys
a=tuple(map(int,sys.argv[1].split('.'))); b=tuple(map(int,sys.argv[2].split('.')))
raise SystemExit(0 if a>b else 1)
PY
}
current_repo_version(){
  if [[ -f "$REPO_DIR/VERSION" ]]; then local v; v="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"; if valid_version "$v"; then printf '%s\n' "$v"; return 0; fi; fi
  printf '0.0.0\n'
}
get_signature(){ local file="$1"; if stat -f '%N|%m|%z' "$file" >/dev/null 2>&1; then stat -f '%N|%m|%z' "$file"; else printf '%s|' "$file"; stat -c '%Y|%s' "$file"; fi; }
already_processed(){ local signature="$1"; [[ -f "$STATE_FILE" ]] && grep -Fqx -- "$signature" "$STATE_FILE" 2>/dev/null; }
mark_processed(){ local signature="$1"; already_processed "$signature" && return 0; printf '%s\n' "$signature" >> "$STATE_FILE"; local tmp_state="$STATE_FILE.tmp.$$"; tail -n 256 "$STATE_FILE" > "$tmp_state" && mv "$tmp_state" "$STATE_FILE"; }
get_latest_zip(){
  local file name version signature current_version best_file="" best_version=""; current_version="$(current_repo_version)"
  for file in "$WATCH_DIR"/pride-bank-v*.zip; do
    [[ -f "$file" ]] || continue; name="${file##*/}"; version="${name#pride-bank-v}"; version="${version%.zip}"; valid_version "$version" || continue
    if version_gt "$current_version" "$version"; then continue; fi
    signature="$(get_signature "$file")"; already_processed "$signature" && continue
    if [[ -z "$best_version" ]] || version_gt "$version" "$best_version"; then best_version="$version"; best_file="$file"; fi
  done
  [[ -n "$best_file" ]] && printf '%s\n' "$best_file"
}
file_stability_signature(){ local file="$1"; if stat -f '%m|%z' "$file" >/dev/null 2>&1; then stat -f '%m|%z' "$file"; else stat -c '%Y|%s' "$file" 2>/dev/null || true; fi; }
wait_until_stable(){ local file="$1" sig1 sig2; while true; do sig1="$(file_stability_signature "$file")"; sleep "$STABLE_SECONDS"; sig2="$(file_stability_signature "$file")"; [[ -n "$sig1" && "$sig1" == "$sig2" ]] && return 0; pb_warn "ZIP is still being downloaded/written..."; done; }
resolve_source_dir(){ local tmp_dir="$1" top_count only_item; rm -rf "$tmp_dir/__MACOSX"; top_count="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"; if [[ "$top_count" == "1" ]]; then only_item="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -print | head -n 1)"; if [[ -d "$only_item" ]]; then printf '%s\n' "$only_item"; return 0; fi; fi; printf '%s\n' "$tmp_dir"; }
validate_release(){
  local source_dir="$1" zip_file="$2" version zip_name zip_version
  [[ -f "$source_dir/VERSION" ]] || { pb_error "Release ZIP does not contain VERSION."; return 1; }
  [[ -f "$source_dir/scripts/deploy.sh" ]] || { pb_error "Release ZIP does not contain scripts/deploy.sh."; return 1; }
  [[ -f "$source_dir/scripts/app_build.sh" ]] || { pb_error "Release ZIP does not contain scripts/app_build.sh."; return 1; }
  [[ -d "$source_dir/PrideBank.xcodeproj" ]] || { pb_error "Release ZIP does not contain PrideBank.xcodeproj."; return 1; }
  [[ -f "$source_dir/homepage/index.html" ]] || { pb_error "Release ZIP does not contain homepage/index.html."; return 1; }
  version="$(tr -d '[:space:]' < "$source_dir/VERSION")"; zip_name="${zip_file##*/}"; zip_version="${zip_name#pride-bank-v}"; zip_version="${zip_version%.zip}"
  [[ "$version" == "$zip_version" ]] || { pb_error "ZIP filename says v$zip_version but VERSION says v$version."; return 1; }
  printf '%s\n' "$version"
}
deploy_current_if_needed(){
  local version recorded; version="$(current_repo_version)"; [[ "$version" != "0.0.0" ]] || return 0; recorded=""; [[ -f "$DEPLOYED_VERSION_FILE" ]] && recorded="$(tr -d '[:space:]' < "$DEPLOYED_VERSION_FILE")"; [[ "$recorded" == "$version" ]] && return 0
  [[ -x "$REPO_DIR/scripts/deploy.sh" ]] || return 0
  pb_section "Completing pending v$version release/deployment"
  if "$ZSH_BIN" "$REPO_DIR/scripts/deploy.sh"; then printf '%s\n' "$version" > "$DEPLOYED_VERSION_FILE"; pb_success "v$version deployment completed."; else pb_error "Pending v$version deployment failed. Source remains installed; restart watcher to retry."; return 1; fi
}
process_zip(){
  local zip_file="$1" signature tmp_dir source_dir version current_version
  signature="$(get_signature "$zip_file")"; already_processed "$signature" && return 0
  pb_banner_info "New Pride Bank package detected"; printf '%b%s%b\n' "$PB_C_CYAN" "$zip_file" "$PB_C_RESET"
  wait_until_stable "$zip_file"; signature="$(get_signature "$zip_file")"; mark_processed "$signature"
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pride-bank-update.XXXXXX")"; log "Unpacking release package..."
  if ! unzip -q "$zip_file" -d "$tmp_dir"; then pb_error "Could not unzip release package: $zip_file"; rm -rf "$tmp_dir"; return 1; fi
  source_dir="$(resolve_source_dir "$tmp_dir")"; if ! version="$(validate_release "$source_dir" "$zip_file")"; then rm -rf "$tmp_dir"; return 1; fi
  current_version="$(current_repo_version)"; if version_gt "$current_version" "$version"; then log "Ignoring older v$version because repository is already v$current_version."; rm -rf "$tmp_dir"; return 0; fi
  if [[ "$version" == "$current_version" ]]; then log "Retrying deployment for current v$version because this ZIP has a new signature."; else log "Release version: v$version (current v$current_version)"; fi
  log "Synchronising repository"; pb_field "FROM:" "$source_dir"; pb_field "TO:" "$REPO_DIR"
  if ! rsync --archive --checksum --delete --exclude='.git/' --exclude='archive/' --exclude='.watch-state/' --exclude='build/' --exclude='xcuserdata/' --exclude='.env' --exclude='.env.*' "$source_dir/" "$REPO_DIR/"; then pb_error "Repository rsync failed."; rm -rf "$tmp_dir"; return 1; fi
  rm -rf "$tmp_dir"; echo; pb_success "Repository files updated"; log "Running deployment"; pb_field "DIR:" "$REPO_DIR"; echo
  cd "$REPO_DIR" || return 1; printf '%b>>>%b %s\n' "$PB_C_MAGENTA" "$PB_C_RESET" "./scripts/deploy.sh"; ./scripts/deploy.sh || return 1
  printf '%s\n' "$version" > "$DEPLOYED_VERSION_FILE"
  pb_banner_success "PRIDE BANK UPDATE + DEPLOYMENT COMPLETED SUCCESSFULLY"
  log "Reloading watcher from the updated repository..."; cleanup; exec "$ZSH_BIN" "$REPO_DIR/scripts/build-watch.sh"
}
report_failure(){ pb_banner_error "PRIDE BANK UPDATE FAILED"; printf '%b%s%b\n' "$PB_C_YELLOW" "The failed ZIP will not auto-run again every five seconds." "$PB_C_RESET" >&2; printf '%s\n' "Fix the problem, then touch/re-download this ZIP to retry, or save a newer release ZIP." >&2; }
pb_banner_info "Pride Bank update watcher started"
pb_field "Watching:" "$WATCH_DIR/$ZIP_PATTERN"; pb_field "Repository:" "$REPO_DIR"; pb_field "Deploy:" "$REPO_DIR/scripts/deploy.sh"; pb_field "Git remote:" "git@github.com:sylwesterdigital/pride-bank.git"; pb_field "Server path:" "/var/www/mojoworks/labs/bank"; pb_field "Poll:" "every ${POLL_SECONDS}s"; pb_field "Stop:" "Ctrl+C"; echo
# Compatibility migration from v0.1.x watchers, which applied source before reloading.
deploy_current_if_needed || true
while true; do latest_zip="$(get_latest_zip)"; if [[ -n "$latest_zip" && -f "$latest_zip" ]]; then process_zip "$latest_zip" || report_failure; fi; printf '\r%b[%s]%b %b● watching%b %s %b— Ctrl+C stops%b' "$PB_C_MUTED" "$(date '+%H:%M:%S')" "$PB_C_RESET" "$PB_C_GREEN" "$PB_C_RESET" "$ZIP_PATTERN" "$PB_C_MUTED" "$PB_C_RESET"; sleep "$POLL_SECONDS"; done
