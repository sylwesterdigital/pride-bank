# Pride — Blocks

Pride is an internal digital economy. Blocks are service units used inside Pride; the product intentionally avoids crypto/trading language.

## Release workflow

Run `./scripts/build-watch.sh` on the macOS development machine and drop versioned ZIP releases into `archive/`. The watcher validates, applies, builds/installs the iOS app when a physical device is available, commits/pushes source, deploys the server components, and resumes watching.

## Real accounts and Blocks ledger

The authoritative balance is PostgreSQL on the Ubuntu server. The iOS app never credits itself. User passwords are scrypt-hashed server-side, API sessions are opaque random tokens stored hashed in PostgreSQL and stored in iOS Keychain, while the six-digit PIN protects the local authenticated session.

Blocks are recorded with immutable double-entry ledger rows. Member transfers and Stripe top-ups are posted atomically in PostgreSQL. Stripe top-ups are credited only from a verified `payment_intent.succeeded` webhook and both Stripe event IDs and PaymentIntent references are unique/idempotent.
Webhook receipt and successful processing are tracked separately: a failed or crashed handler does not suppress Stripe retries, while concurrent/replayed events cannot credit the same PaymentIntent twice. Full refunds reverse the top-up; partial refunds freeze the account for reconciliation.

## Stripe

The Stripe secret key and webhook secret are server-only. The release never contains them. PaymentIntent amounts/packages are chosen by the server, not trusted from the iPhone. The Stripe account represented by `STRIPE_SECRET_KEY` is the account that receives real money; configure that Stripe account for **WORKWORK.FUN LTD**.

The watcher bootstraps `/etc/pride-bank/server.env` itself with generated database credentials and session pepper. When Stripe account credentials are missing, the foreground watcher prompts once (secret input hidden), stores them root-only on Ubuntu, and continues. `STRIPE_MODE=test` is strongly recommended until end-to-end reconciliation is verified; switching to `live` requires an `sk_live_` key and is explicit.

The API listens only on `127.0.0.1:4317`. The bootstrap may add the Pride `/api/` proxy only when it can prove exactly one HTTPS nginx site serves the configured Pride public root; ambiguous shared nginx layouts are left untouched and reported instead of guessed. The verified public API URL is then written back into the local release profile automatically.

## App Store payment policy

Stripe PaymentSheet is included for direct development and distribution contexts where it is permitted. Blocks are a digital in-app unit, so App Store distribution generally requires Apple In-App Purchase for purchasing Blocks. The server ledger is payment-rail independent so a StoreKit settlement adapter can credit the same ledger after App Store server verification.

## Safe Ubuntu bootstrap

The watcher owns the complete release sequence. On Ubuntu it treats the host as shared production infrastructure: existing PostgreSQL/nginx installations are inspected and reused without global configuration rewrites; only Pride-specific database/user, service, config, release, state and backup resources are created. Missing packages are installed only when the corresponding service/tool is genuinely absent. Existing ambiguous or unhealthy shared services cause a precise stop instead of an automatic repair.

Backend runtime layout: `/opt/pride-bank` (releases/current), `/etc/pride-bank` (root-only config), `/var/lib/pride-bank` (state), `/var/backups/pride-bank` (Pride-only backups). The public site remains `/var/www/mojoworks/labs/bank`.

The only unavoidable one-time external input is Stripe account credentials (`STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`) and, when an existing shared web server cannot be unambiguously mapped to Pride, the HTTPS site mapping. Everything else is detected/provisioned by the release sequence. The webhook endpoint/signing secret is created automatically when possible.

PostgreSQL administration commands run from `/` and migrations are streamed over stdin, so the `postgres` OS user never needs access to `/opt/pride-bank` or `/var/backups/pride-bank`. The application source remains root-owned and is readable only by the dedicated `pride-bank` service group.

Canonical public origin: `https://mojoworks.xyz/labs/bank`. This follows the supplied Shar deployment convention; nginx bootstrap proves the live mapping before any config change and does not alter the `.click`/`www` aliases.

### iOS payment SDK compatibility

The iOS target uses Stripe PaymentSheet through Swift Package Manager and pins `stripe-ios-spm` exactly to `25.17.0`. Do not change this to an open-ended `upToNextMajorVersion` requirement: unattended watcher builds run on the verified Xcode 16.2 / iPhoneOS 18.2 toolchain, and newer Stripe 26.x source can require newer Apple SDK symbols. Upgrade the pin only together with an explicit Xcode compatibility test.
