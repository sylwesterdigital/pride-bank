#!/bin/zsh
# Foreground release watcher for Pride Bank / Blocks.
# Single-command workflow: watch archive -> apply -> verify -> deploy -> continue watching.
set -u
set -o pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
source "$SCRIPT_DIR/terminal-style.sh"

WATCH_DIR="${WATCH_DIR:-$ROOT/archive}"
STATE_DIR="${STATE_DIR:-$ROOT/.watch-state}"
STATE_FILE="$STATE_DIR/processed-signatures"
DEPLOYED_VERSION_FILE="$STATE_DIR/deployed-version"
LOCK_DIR="${TMPDIR:-/tmp}/pride-bank-watch.lock"
ZIP_PATTERN='pride-bank-v*.zip'
POLL_SECONDS="${POLL_SECONDS:-3}"
STABLE_SECONDS="${STABLE_SECONDS:-2}"
ZSH_BIN="${ZSH_BIN:-$(command -v zsh 2>/dev/null || command -v bash)}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-$ROOT/scripts/deploy.sh}"

mkdir -p "$WATCH_DIR" "$STATE_DIR"

cleanup() { rm -rf "$LOCK_DIR"; }
trap 'cleanup; echo; pb_warn "Watcher stopped."; exit 130' INT TERM
trap cleanup EXIT

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  pb_error "Pride Bank watcher is already running."
  exit 1
fi

valid_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }

version_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  (( a1 > b1 || (a1 == b1 && (a2 > b2 || (a2 == b2 && a3 > b3))) ))
}

current_version() {
  local version='0.0.0'
  if [[ -f "$ROOT/VERSION" ]]; then
    version="$(tr -d '[:space:]' < "$ROOT/VERSION")"
    valid_version "$version" || version='0.0.0'
  fi
  printf '%s\n' "$version"
}

file_signature() {
  local file_name="$1"
  if stat -f '%N|%m|%z' "$file_name" >/dev/null 2>&1; then
    stat -f '%N|%m|%z' "$file_name"
  else
    printf '%s|' "$file_name"
    stat -c '%Y|%s' "$file_name"
  fi
}

stability_signature() {
  local file_name="$1"
  if stat -f '%m|%z' "$file_name" >/dev/null 2>&1; then
    stat -f '%m|%z' "$file_name"
  else
    stat -c '%Y|%s' "$file_name" 2>/dev/null || true
  fi
}

already_processed() {
  local signature="$1"
  [[ -f "$STATE_FILE" ]] && grep -Fqx -- "$signature" "$STATE_FILE" 2>/dev/null
}

mark_processed() {
  local signature="$1"
  already_processed "$signature" && return 0
  printf '%s\n' "$signature" >> "$STATE_FILE"
  local compact_file="$STATE_FILE.tmp.$$"
  tail -n 256 "$STATE_FILE" > "$compact_file" && mv "$compact_file" "$STATE_FILE"
}

wait_until_stable() {
  local file_name="$1" before after
  while true; do
    before="$(stability_signature "$file_name")"
    sleep "$STABLE_SECONDS"
    after="$(stability_signature "$file_name")"
    if [[ -n "$before" && "$before" == "$after" ]]; then
      return 0
    fi
    pb_warn "ZIP is still being copied or downloaded; waiting."
  done
}

resolve_source_dir() {
  local temp_dir="$1" count only_item
  rm -rf "$temp_dir/__MACOSX"
  count="$(find "$temp_dir" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"
  if [[ "$count" == '1' ]]; then
    only_item="$(find "$temp_dir" -mindepth 1 -maxdepth 1 -print | head -n 1)"
    if [[ -d "$only_item" ]]; then
      printf '%s\n' "$only_item"
      return 0
    fi
  fi
  printf '%s\n' "$temp_dir"
}

zip_version_from_name() {
  local zip_name="${1##*/}"
  local version="${zip_name#pride-bank-v}"
  printf '%s\n' "${version%.zip}"
}

latest_candidate() {
  local file_name version signature current best_file='' best_version=''
  current="$(current_version)"
  for file_name in "$WATCH_DIR"/pride-bank-v*.zip; do
    [[ -f "$file_name" ]] || continue
    version="$(zip_version_from_name "$file_name")"
    valid_version "$version" || continue
    if version_gt "$current" "$version"; then
      continue
    fi
    signature="$(file_signature "$file_name")"
    already_processed "$signature" && continue
    if [[ -z "$best_version" ]] || version_gt "$version" "$best_version"; then
      best_file="$file_name"
      best_version="$version"
    fi
  done
  [[ -n "$best_file" ]] && printf '%s\n' "$best_file"
}

validate_release() {
  local source_dir="$1" zip_file="$2" file_version package_version
  [[ -f "$source_dir/VERSION" ]] || { pb_error "Release is missing VERSION."; return 1; }
  [[ -x "$source_dir/scripts/verify.sh" ]] || { pb_error "Release is missing executable scripts/verify.sh."; return 1; }
  [[ -x "$source_dir/scripts/apply-release.sh" ]] || { pb_error "Release is missing executable scripts/apply-release.sh."; return 1; }
  [[ -x "$source_dir/scripts/deploy.sh" ]] || { pb_error "Release is missing executable scripts/deploy.sh."; return 1; }
  [[ -f "$source_dir/web/index.html" ]] || { pb_error "Release is missing web/index.html."; return 1; }

  file_version="$(zip_version_from_name "$zip_file")"
  package_version="$(tr -d '[:space:]' < "$source_dir/VERSION")"
  valid_version "$package_version" || { pb_error "Invalid VERSION in release: $package_version"; return 1; }
  [[ "$file_version" == "$package_version" ]] || {
    pb_error "ZIP filename says v$file_version but VERSION says v$package_version."
    return 1
  }
  printf '%s\n' "$package_version"
}

deployed_version() {
  [[ -f "$DEPLOYED_VERSION_FILE" ]] || return 0
  tr -d '[:space:]' < "$DEPLOYED_VERSION_FILE"
}

deploy_current_if_needed() {
  local version deployed
  version="$(current_version)"
  [[ "$version" != '0.0.0' ]] || return 0
  deployed="$(deployed_version)"
  [[ "$deployed" == "$version" ]] && return 0

  [[ -x "$DEPLOY_SCRIPT" ]] || {
    pb_error "Deployment script missing or not executable: $DEPLOY_SCRIPT"
    return 1
  }

  pb_info "Deploying Pride Bank v$version"
  if "$ZSH_BIN" "$DEPLOY_SCRIPT"; then
    printf '%s\n' "$version" > "$DEPLOYED_VERSION_FILE"
    pb_ok "Deployment recorded for v$version."
    return 0
  fi

  pb_error "Deployment failed for v$version."
  pb_warn "Source remains applied. Restart this watcher to retry deployment, or drop a newer release ZIP."
  return 1
}

process_zip() {
  local zip_file="$1" signature temp_dir source_dir release_version installed_version

  wait_until_stable "$zip_file"
  signature="$(file_signature "$zip_file")"
  already_processed "$signature" && return 0

  # Attempt each exact file signature once. Replacing/touching it opts in to retry.
  mark_processed "$signature"

  pb_info "Release detected: ${zip_file##*/}"
  python3 "$ROOT/scripts/verify-archive.py" "$zip_file" || return 1

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pride-bank-update.XXXXXX")"
  if ! unzip -q "$zip_file" -d "$temp_dir"; then
    pb_error "Could not extract release ZIP."
    rm -rf "$temp_dir"
    return 1
  fi

  source_dir="$(resolve_source_dir "$temp_dir")"
  release_version="$(validate_release "$source_dir" "$zip_file")" || { rm -rf "$temp_dir"; return 1; }
  installed_version="$(current_version)"

  if version_gt "$installed_version" "$release_version"; then
    pb_warn "Ignoring older v$release_version; repository is v$installed_version."
    rm -rf "$temp_dir"
    return 0
  fi

  if [[ "$installed_version" == "$release_version" ]]; then
    pb_info "Applying same-version v$release_version with a new file signature."
  else
    pb_info "Updating v$installed_version → v$release_version"
  fi

  "$ZSH_BIN" "$ROOT/scripts/apply-release.sh" "$source_dir" || { rm -rf "$temp_dir"; return 1; }
  rm -rf "$temp_dir"

  pb_ok "Pride Bank v$release_version source applied and verified."
  pb_info "Reloading watcher from the updated release."
  cleanup
  exec "$ZSH_BIN" "$ROOT/scripts/build-watch.sh"
}

pb_info "Pride Bank release watcher"
printf 'Watching:    %s/%s\n' "$WATCH_DIR" "$ZIP_PATTERN"
printf 'Repository:  %s\n' "$ROOT"
printf 'Current:     v%s\n' "$(current_version)"
printf 'Deploy:      %s\n' "$ROOT/scripts/deploy.sh"
printf 'Remote path: /var/www/mojoworks/labs/bank\n'
printf 'Stop:        Ctrl+C\n\n'

# Important for the v0.1.2 -> v0.1.3 transition: the old watcher applies the
# new source and execs this watcher. The deployed-version marker is absent, so
# this startup path performs the deployment without requiring a second command.
deploy_current_if_needed || true
printf '\n'

while true; do
  candidate="$(latest_candidate)"
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    if ! process_zip "$candidate"; then
      pb_error "Release failed. This exact ZIP will not run again automatically."
      pb_warn "Replace or touch it to retry intentionally, or add a newer release."
    fi
  fi
  printf '\r%b[%s]%b %b● watching%b %s %b— Ctrl+C stops%b' "$PB_MUTED" "$(date '+%H:%M:%S')" "$PB_RESET" "$PB_GREEN" "$PB_RESET" "$ZIP_PATTERN" "$PB_MUTED" "$PB_RESET"
  sleep "$POLL_SECONDS"
done
