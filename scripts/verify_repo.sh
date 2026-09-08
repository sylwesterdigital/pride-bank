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
required=(README.md CHANGELOG.md .gitignore PrideBank.xcodeproj/project.pbxproj PrideBank/PrideBankApp.swift PrideBank/AppState.swift PrideBank/SecurePINStore.swift PrideBank/SecureSessionStore.swift PrideBank/APIClient.swift PrideBank/StripeTopUpView.swift PrideBank/DesignSystem.swift PrideBank/RootView.swift PrideBank/Info.plist PrideBank/Assets.xcassets/Contents.json PrideBank/Assets.xcassets/PrideBrand.imageset/Contents.json PrideBank/Assets.xcassets/AppIcon.appiconset/Contents.json brand/pride-bank.svg homepage/index.html homepage/assets/pride-bank.svg homepage/assets/pride-bank-icon.png homepage/app.css homepage/app.js scripts/build-watch.sh scripts/deploy.sh scripts/release_and_deploy.sh scripts/deploy_homepage.sh scripts/release_profile.sh scripts/app_build.sh scripts/deploy_backend.sh scripts/package-release.sh server/package.json server/server.env.example server/src/index.js server/src/auth.js server/src/db.js server/src/ledger.js server/src/stripe.js server/migrations/001_core.sql server/migrations/002_ledger_security.sql server/migrations/003_webhook_delivery.sql server/scripts/pride-blocks.service server/scripts/nginx-location.conf server/scripts/bootstrap_ubuntu.sh server/scripts/set_stripe_keys.sh server/scripts/configure_nginx.py server/scripts/configure-stripe.js)
for required_file in "${required[@]}"; do [[ -f "$required_file" ]] || fail "Missing required file: $required_file"; done
grep -Eq '^/archive/$|^archive/$' .gitignore || fail "archive/ must be Git ignored"
grep -Fq "## [$VERSION]" CHANGELOG.md || fail "CHANGELOG.md is not updated for $VERSION"
grep -Fq 'case splash' PrideBank/AppState.swift || fail "Splash state missing"
grep -Fq 'case identity' PrideBank/AppState.swift || fail "Identity onboarding state missing"
grep -Fq 'case createPIN' PrideBank/AppState.swift || fail "PIN creation state missing"
grep -Fq 'kSecClassGenericPassword' PrideBank/SecurePINStore.swift || fail "Keychain PIN storage missing"
grep -Fq 'SHA256.hash' PrideBank/SecurePINStore.swift || fail "PIN digest missing"
grep -Fq 'stage = .locked' PrideBank/AppState.swift || fail "Protected locked state missing"
! grep -Fq '12_480' PrideBank/AppState.swift || fail "Hard-coded demo Blocks balance must not exist"
grep -Fq 'APIClient.shared.me' PrideBank/AppState.swift || fail "Blocks balance is not server-backed"
grep -Fq 'SecureSessionStore' PrideBank/AppState.swift || fail "Secure server session storage missing"
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
grep -Fq 'StripePaymentSheet' PrideBank.xcodeproj/project.pbxproj || fail "Stripe iOS PaymentSheet package missing"
grep -Fq 'payment_intent.succeeded' server/src/stripe.js || fail "Stripe webhook settlement missing"
grep -Fq 'constructEvent' server/src/stripe.js || fail "Stripe webhook signature verification missing"
grep -Fq 'post_topup_credit' server/migrations/001_core.sql || fail "Atomic top-up ledger posting missing"
grep -Fq 'ledger_immutable' server/migrations/001_core.sql || fail "Immutable ledger protection missing"
grep -Fq 'Idempotency-Key' PrideBank/APIClient.swift || fail "iOS top-up idempotency key missing"
grep -Fq 'WORKWORK.FUN LTD' server/server.env.example || fail "Expected merchant legal name missing"
grep -Fq '/opt/pride-bank' server/scripts/pride-blocks.service || fail "Backend service must run outside the public webroot"
grep -Fq 'Refusing automatic host bootstrap on non-Ubuntu' server/scripts/bootstrap_ubuntu.sh || fail "Ubuntu safety guard missing"
grep -Fq 'Stripe secret key (input hidden)' scripts/deploy_backend.sh || fail "Watcher-owned one-time Stripe credential prompt missing"
grep -Fq 'refusing a possible naming collision' server/scripts/bootstrap_ubuntu.sh || fail "PostgreSQL collision guard missing"
grep -Fq 'nginx -t' server/scripts/bootstrap_ubuntu.sh || fail "nginx validation/rollback guard missing"
grep -Fq 'pg_dump -Fc pride_bank' server/scripts/bootstrap_ubuntu.sh || fail "Pride database backup guard missing"
grep -Fq 'RELEASE_VERSION="${PB_VERSION:?PB_VERSION missing}"' server/scripts/bootstrap_ubuntu.sh || fail "Ubuntu bootstrap must keep Pride release version separate from /etc/os-release VERSION"
grep -Fq 'as_postgres(){ ( cd / && runuser -u postgres -- "$@" ); }' server/scripts/bootstrap_ubuntu.sh || fail "PostgreSQL admin wrapper must run from a neutral working directory"
grep -Fq 'cat "$migration" | as_postgres psql' server/scripts/bootstrap_ubuntu.sh || fail "PostgreSQL migration SQL must be streamed over stdin"
! grep -Fq 'psql -v ON_ERROR_STOP=1 pride_bank -f "$migration"' server/scripts/bootstrap_ubuntu.sh || fail "Migration runner must not require postgres to traverse the release directory"
grep -Fq 'as_postgres pg_dump -Fc pride_bank > "$DUMP"' server/scripts/bootstrap_ubuntu.sh || fail "Pride database dump must be streamed into the root-owned backup path"
grep -Fq 'chown root:pride-bank "$APP_ROOT" "$APP_ROOT/releases"' server/scripts/bootstrap_ubuntu.sh || fail "Dedicated service group must have controlled application-tree traversal"
grep -Fq 'runuser -u pride-bank -- test -r "$RELEASE_DIR/src/index.js"' server/scripts/bootstrap_ubuntu.sh || fail "Backend activation must verify service-user readability first"
grep -Fq 'ledger_entries_balanced' server/migrations/002_ledger_security.sql || fail "Deferred double-entry balance check missing"
grep -Fq 'processing_started_at' server/migrations/003_webhook_delivery.sql || fail "Retry-safe Stripe webhook delivery state missing"
grep -Fq "processed_at IS NULL" server/src/stripe.js || fail "Stripe duplicate handling must distinguish received from successfully processed events"
grep -Fq "processing_started_at=NULL, processing_error=\$2" server/src/stripe.js || fail "Failed Stripe webhooks must release their processing claim for retry"
grep -Fq "stripe_partial_refund" server/src/stripe.js || fail "Partial Stripe refunds must freeze the account for reconciliation"
grep -Fq 'REVOKE ALL ON ledger_transactions, ledger_entries FROM pride_app' server/migrations/002_ledger_security.sql || fail "Ledger direct-write restriction missing"
grep -Fq 'REVOKE ALL ON blocks_accounts FROM pride_app' server/migrations/002_ledger_security.sql || fail "Blocks balance table direct-write restriction missing"
grep -Fq 'create_member_blocks_account' server/src/auth.js || fail "Registration must use the constrained member-account function"
grep -Eq '^STRIPE_SECRET_KEY=sk_(live|test)_[A-Za-z0-9]{16,}$' server/server.env.example && fail "Live/test Stripe secret must not be stored in server/server.env.example" || true
grep -Fq -- "--exclude='.env.*'" scripts/build-watch.sh || fail "Watcher must exclude real .env.* secret files"
grep -Fq -- "--exclude='.env.*'" scripts/package-release.sh || fail "Release packager must exclude real .env.* secret files"
grep -Fq './scripts/deploy_backend.sh' scripts/release_and_deploy.sh || fail "Release does not deploy Blocks API"
python3 - <<'PYORDER'
from pathlib import Path
s=Path('scripts/release_and_deploy.sh').read_text()
assert s.index('./scripts/deploy_backend.sh') < s.index('./scripts/app_build.sh'), 'backend must be verified before mobile build'
PYORDER
grep -Fq 'PRIDE_API_BASE_URL="$API_BASE_URL"' scripts/app_build.sh || fail "iOS build does not inject API URL"
grep -Fq '<string>$(MARKETING_VERSION)</string>' PrideBank/Info.plist || fail "iOS marketing version must derive from Xcode settings"
grep -Fq '<string>$(CURRENT_PROJECT_VERSION)</string>' PrideBank/Info.plist || fail "iOS build version must derive from Xcode settings"
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
if command -v node >/dev/null 2>&1; then node --check homepage/app.js; (cd server && npm run check --silent); fi
if command -v swift >/dev/null 2>&1; then swiftc -parse PrideBank/PrideBankApp.swift PrideBank/AppState.swift PrideBank/SecurePINStore.swift PrideBank/SecureSessionStore.swift PrideBank/APIClient.swift PrideBank/StripeTopUpView.swift PrideBank/DesignSystem.swift PrideBank/RootView.swift >/dev/null; fi
pb_success "Repository verification passed for v$VERSION"
