#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/scripts/terminal_style.sh"
cd "$ROOT"
fail(){ pb_error "$*"; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid VERSION: $VERSION"
required=(README.md CHANGELOG.md .gitignore PrideBank.xcodeproj/project.pbxproj PrideBank/PrideBankApp.swift PrideBank/AppState.swift PrideBank/SecurePINStore.swift PrideBank/DesignSystem.swift PrideBank/RootView.swift PrideBank/Info.plist homepage/index.html homepage/app.css homepage/app.js scripts/build-watch.sh scripts/deploy.sh scripts/release_and_deploy.sh scripts/deploy_homepage.sh scripts/release_profile.sh scripts/app_build.sh scripts/package-release.sh)
for required_file in "${required[@]}"; do [[ -f "$required_file" ]] || fail "Missing required file: $required_file"; done
grep -Eq '^/archive/$|^archive/$' .gitignore || fail "archive/ must be Git ignored"
grep -Fq "## [$VERSION]" CHANGELOG.md || fail "CHANGELOG.md is not updated for $VERSION"
grep -Fq 'case splash' PrideBank/AppState.swift || fail "Splash state missing"
grep -Fq 'case identity' PrideBank/AppState.swift || fail "Identity onboarding state missing"
grep -Fq 'case createPIN' PrideBank/AppState.swift || fail "PIN creation state missing"
grep -Fq 'kSecClassGenericPassword' PrideBank/SecurePINStore.swift || fail "Keychain PIN storage missing"
grep -Fq 'SHA256.hash' PrideBank/SecurePINStore.swift || fail "PIN digest missing"
grep -Fq 'stage = .locked' PrideBank/AppState.swift || fail "Protected locked state missing"
grep -Fq '12_480' PrideBank/AppState.swift || fail "Demo Blocks balance missing"
grep -Fq 'PrideBank.xcodeproj' scripts/build-watch.sh || fail "Watcher release validation is not app-aware"
grep -Fq './scripts/deploy.sh' scripts/build-watch.sh || fail "Watcher does not own deployment flow"
grep -Fq '/var/www/mojoworks/labs/bank' scripts/release_profile.sh || fail "Ubuntu deployment path is not pinned"
grep -Fq 'xcodebuild' scripts/app_build.sh || fail "Mobile build step missing"
# Product-facing text guard. Internal technical comments and scripts are intentionally excluded.
if grep -Eiv 'crypto\.' homepage/app.js | grep -Eiq '\b(wallet|token|coin|crypto|blockchain|staking|on-chain|web3|withdraw|metaverse|nft|floor price)\b'; then fail "Prohibited product language found in user-facing UI"; fi
if grep -Eiq '\b(wallet|token|coin|crypto|blockchain|staking|on-chain|web3|withdraw|metaverse|nft|floor price)\b' homepage/index.html PrideBank/RootView.swift; then fail "Prohibited product language found in user-facing UI"; fi
if command -v node >/dev/null 2>&1; then node --check homepage/app.js; fi
if command -v swift >/dev/null 2>&1; then swiftc -parse PrideBank/PrideBankApp.swift PrideBank/AppState.swift PrideBank/SecurePINStore.swift PrideBank/DesignSystem.swift PrideBank/RootView.swift >/dev/null; fi
pb_success "Repository verification passed for v$VERSION"
