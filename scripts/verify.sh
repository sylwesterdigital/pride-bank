#!/bin/zsh
set -e
set -u
set -o pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/terminal-style.sh"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { pb_error "Invalid VERSION: $VERSION"; exit 1; }

required=(
  "$ROOT/README.md"
  "$ROOT/CHANGELOG.md"
  "$ROOT/.gitignore"
  "$ROOT/web/index.html"
  "$ROOT/web/styles.css"
  "$ROOT/web/app.js"
  "$ROOT/scripts/build-watch.sh"
  "$ROOT/scripts/bootstrap-watch.sh"
  "$ROOT/scripts/apply-release.sh"
  "$ROOT/scripts/deploy.sh"
  "$ROOT/scripts/release_profile.sh"
  "$ROOT/scripts/package-release.sh"
  "$ROOT/scripts/verify-archive.py"
  "$ROOT/scripts/verify-product-language.py"
)

for required_file in "${required[@]}"; do
  [[ -f "$required_file" ]] || { pb_error "Missing required file: ${required_file#$ROOT/}"; exit 1; }
done

[[ ! -e "$ROOT/scripts/dev.sh" ]] || { pb_error "scripts/dev.sh must not exist; watcher must not start a local demo server."; exit 1; }
if grep -Fq 'http.server' "$ROOT/scripts/build-watch.sh"; then
  pb_error "Watcher must not start a local HTTP server."
  exit 1
fi
grep -Fq 'deploy_current_if_needed' "$ROOT/scripts/build-watch.sh" || { pb_error "Watcher must own deployment lifecycle."; exit 1; }
grep -Fq 'scripts/deploy.sh' "$ROOT/scripts/build-watch.sh" || { pb_error "Watcher must call the deployment pipeline."; exit 1; }
grep -Fq '/var/www/mojoworks/labs/bank' "$ROOT/scripts/release_profile.sh" || { pb_error "Deployment profile must pin the expected Ubuntu path."; exit 1; }

grep -Eq '^/archive/$|^archive/$' "$ROOT/.gitignore" || { pb_error "archive/ must be Git ignored"; exit 1; }
grep -Fq "## [$VERSION]" "$ROOT/CHANGELOG.md" || { pb_error "CHANGELOG.md missing release $VERSION"; exit 1; }
python3 "$ROOT/scripts/verify-product-language.py"

python3 -m py_compile "$ROOT/scripts/verify-archive.py" "$ROOT/scripts/verify-product-language.py"
rm -rf "$ROOT/scripts/__pycache__"

if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/scripts/build-watch.sh" "$ROOT/scripts/bootstrap-watch.sh" "$ROOT/scripts/apply-release.sh" "$ROOT/scripts/deploy.sh" "$ROOT/scripts/release_profile.sh" "$ROOT/scripts/package-release.sh"
else
  bash -n "$ROOT/scripts/build-watch.sh" "$ROOT/scripts/bootstrap-watch.sh" "$ROOT/scripts/apply-release.sh" "$ROOT/scripts/deploy.sh" "$ROOT/scripts/release_profile.sh" "$ROOT/scripts/package-release.sh"
  pb_warn "zsh not installed in this environment; shell syntax checked with bash-compatible parser."
fi

if command -v node >/dev/null 2>&1; then
  node --check "$ROOT/web/app.js"
else
  pb_warn "Node not installed; JavaScript syntax check skipped."
fi

pb_ok "Verification passed for v$VERSION"
