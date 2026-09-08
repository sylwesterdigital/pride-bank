# Changelog

## [0.3.2] - 2026-09-08

- Added shared-Ubuntu-safe bootstrap: inspect first, install only genuinely missing fresh-host prerequisites, and never rewrite PostgreSQL global configuration.
- Isolated backend code under `/opt/pride-bank`, config under `/etc/pride-bank`, state under `/var/lib/pride-bank`, and backups under `/var/backups/pride-bank`.
- Added Pride-only PostgreSQL role/database provisioning with collision checks, pre-migration backups, additive migrations, ledger role hardening, and deferred double-entry balance enforcement.
- Added conservative nginx integration: modify exactly one unambiguous HTTPS server block serving the Pride public root, validate with `nginx -t`, reload only, and restore on validation failure.
- Added automatic generation of database credentials/session pepper and automatic Stripe webhook creation once the two Stripe account keys are supplied.
- Reordered release flow so the server is bootstrapped and verified before the iOS app is built/installed; the watcher no longer requires a manually exported API URL.
- Fixed iOS version metadata to derive from Xcode build settings.

## [0.3.1] - 2026-09-08

### Fixed
- Fixed the v0.3.0 watcher transition that stripped `server/.env.example` before repository verification.
- Renamed the safe configuration template to `server/server.env.example` so both the already-running v0.3.0 watcher and future watchers preserve it while still excluding all real `.env` secret files.
- Updated backend deployment to copy the safe template to `/etc/pride-bank/server.env.example` when server secrets have not yet been provisioned.
- Added release checks proving secret `.env` files are excluded while the safe template is present.

## [0.3.0] - 2026-09-08

- Replaced demo-only balances with a PostgreSQL-backed Blocks account and immutable double-entry ledger.
- Added real user registration, opaque server sessions, Keychain session storage, and server-backed balance/activity.
- Added Stripe PaymentIntent top-ups with fixed service packages, webhook signature verification, idempotent settlement, refunds/dispute account freezing, and WORKWORK.FUN LTD merchant metadata.
- Added Stripe iOS PaymentSheet integration for permitted/direct-development distribution.
- Added Ubuntu Blocks API deployment, migrations, systemd service template, and nginx reverse-proxy include.
- Added safety gates: no client-side crediting, no secrets in Git/ZIP, HTTPS API requirement, server environment validation, and Stripe account startup verification.

## [0.2.4] - 2026-09-08

### Fixed
- Added the required `CFBundleExecutable` entry to the native iOS `Info.plist`, resolving physical-device installation failure after an otherwise successful signed build.
- Added repository verification for the executable bundle metadata.
- Added a post-build pre-install guard that verifies `CFBundleExecutable` exists and points to an executable file inside `PrideBank.app` before `devicectl` is allowed to install it.

## [0.2.3] - 2026-09-08

- Adopt the supplied Pride flag-dog artwork as the canonical brand mark across Pride product surfaces.
- Add the mark to the native iOS app icon, splash, welcome flow and authenticated header.
- Add the same mark to the hosted app splash, onboarding, authenticated header, favicon and Apple touch icon.
- Store the original supplied SVG unchanged at `brand/pride-bank.svg`; platform renditions are generated from that source.
- Add verification that prevents the mobile/web products from drifting away from the canonical brand asset.

## [0.2.2] - 2026-09-08

- Match the supplied Shar iOS signing workflow instead of guessing a Keychain team.
- Default to the known Xcode development team `5P9V78UZAC`, with explicit environment overrides supported.
- Derive a team-specific Pride Bank bundle identifier for automatic provisioning.
- Use CoreDevice (`devicectl`) discovery/install/launch semantics aligned with Shar.
- Verify the built app code signature and actual bundle identifier before installation.
- Keep physical-device deployment owned by the release watcher; no additional user command is required.

## [0.2.1] - 2026-09-08

- Detect a connected, trusted physical iOS device from the watcher-owned release flow.
- Build the native app for the selected iPhone/iPad with automatic development signing.
- Install the resulting app with `xcrun devicectl` and launch it automatically.
- Refuse ambiguous multi-device deployment instead of guessing.
- Fail visibly when an attached device is locked, untrusted, or unavailable.
- Fall back to a simulator compile check only when no physical device is attached.

## [0.2.0] - 2026-09-08

- Rebuilt the release workflow around the supplied Shar watcher/deploy structure.
- Added a native SwiftUI iOS application project.
- Added splash, first-run welcome, identity creation, six-digit PIN setup and locked/unlocked states.
- Added a protected Home / Blocks experience with send, request and add actions.
- Added Shop, Worlds and Profile foundations.
- PIN verification uses a salted SHA-256 digest stored in the iOS Keychain; the PIN itself is never stored.
- Added a responsive web demo of the same protected onboarding flow for Ubuntu deployment.
- Pinned deployment to `/var/www/mojoworks/labs/bank`.
- Removed the invented local preview-server lifecycle from the watcher.
