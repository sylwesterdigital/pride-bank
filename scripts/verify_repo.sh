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
required=(README.md CHANGELOG.md .gitignore PrideBank.xcodeproj/project.pbxproj PrideBank/PrideBankApp.swift PrideBank/AppState.swift PrideBank/SecurePINStore.swift PrideBank/DesignSystem.swift PrideBank/RootView.swift PrideBank/Info.plist PrideBank/Assets.xcassets/Contents.json PrideBank/Assets.xcassets/PrideBrand.imageset/Contents.json PrideBank/Assets.xcassets/AppIcon.appiconset/Contents.json brand/pride-bank.svg homepage/index.html homepage/assets/pride-bank.svg homepage/assets/pride-bank-icon.png homepage/app.css homepage/app.js scripts/build-watch.sh scripts/deploy.sh scripts/release_and_deploy.sh scripts/deploy_homepage.sh scripts/release_profile.sh scripts/app_build.sh scripts/package-release.sh)
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
grep -Fq 'Image("PrideBrand")' PrideBank/DesignSystem.swift || fail "Canonical Pride brand is not used in the native UI"
grep -Fq 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon' PrideBank.xcodeproj/project.pbxproj || fail "iOS app icon asset catalog is not configured"
grep -Fq '<key>CFBundleExecutable</key>' PrideBank/Info.plist || fail "iOS Info.plist is missing CFBundleExecutable"
grep -Fq '<string>$(EXECUTABLE_NAME)</string>' PrideBank/Info.plist || fail "iOS CFBundleExecutable must resolve from EXECUTABLE_NAME"
[[ "$(shasum -a 256 brand/pride-bank.svg | awk '{print $1}')" == "$(shasum -a 256 homepage/assets/pride-bank.svg | awk '{print $1}')" ]] || fail "Hosted brand SVG differs from canonical brand source"
grep -Fq 'assets/pride-bank.svg' homepage/index.html || fail "Hosted favicon is not using the canonical Pride mark"
grep -Fq 'assets/pride-bank.svg' homepage/app.js || fail "Hosted app is not using the canonical Pride mark"
grep -Fq 'PrideBank.xcodeproj' scripts/build-watch.sh || fail "Watcher release validation is not app-aware"
grep -Fq './scripts/deploy.sh' scripts/build-watch.sh || fail "Watcher does not own deployment flow"
grep -Fq '/var/www/mojoworks/labs/bank' scripts/release_profile.sh || fail "Ubuntu deployment path is not pinned"
grep -Fq 'xcodebuild' scripts/app_build.sh || fail "Mobile build step missing"
grep -Fq 'devicectl list devices' scripts/app_build.sh || fail "Physical iOS CoreDevice discovery missing"
grep -Fq 'Debug-iphoneos/PrideBank.app' scripts/app_build.sh || fail "Physical iOS app bundle handling missing"
grep -Fq '5P9V78UZAC' scripts/app_build.sh || fail "Known Shar-compatible Apple development team default missing"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"' scripts/app_build.sh || fail "Team-specific iOS bundle identifier override missing"
grep -Fq 'codesign --verify' scripts/app_build.sh || fail "Signed app verification missing"
grep -Fq 'devicectl device install app' scripts/app_build.sh || fail "Physical iOS install step missing"
grep -Fq 'devicectl device process launch' scripts/app_build.sh || fail "Physical iOS launch step missing"
if grep -Fq -- '-sdk iphonesimulator' scripts/app_build.sh && ! grep -Fq 'Skipping device install' scripts/app_build.sh; then fail "Simulator-only app build detected"; fi
# Product-facing text guard. Internal technical comments and scripts are intentionally excluded.
if grep -Eiv 'crypto\.' homepage/app.js | grep -Eiq '\b(wallet|token|coin|crypto|blockchain|staking|on-chain|web3|withdraw|metaverse|nft|floor price)\b'; then fail "Prohibited product language found in user-facing UI"; fi
if grep -Eiq '\b(wallet|token|coin|crypto|blockchain|staking|on-chain|web3|withdraw|metaverse|nft|floor price)\b' homepage/index.html PrideBank/RootView.swift; then fail "Prohibited product language found in user-facing UI"; fi
if command -v node >/dev/null 2>&1; then node --check homepage/app.js; fi
if command -v swift >/dev/null 2>&1; then swiftc -parse PrideBank/PrideBankApp.swift PrideBank/AppState.swift PrideBank/SecurePINStore.swift PrideBank/DesignSystem.swift PrideBank/RootView.swift >/dev/null; fi
pb_success "Repository verification passed for v$VERSION"
