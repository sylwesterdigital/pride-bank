# Changelog

## [0.1.3] - 2026-09-08

### Fixed
- Removed the unrequested local HTTP demo lifecycle from `build-watch.sh`.
- Removed `scripts/dev.sh` from the release.
- Aligned the watcher with the supplied Shar release model: ZIP detection → authoritative sync → verification → deployment pipeline → continue watching.
- Added automatic source commit/push and Ubuntu web deployment through `scripts/deploy.sh`.
- Added a private Pride Bank deployment profile that can import the existing Rantlist or Shar SSH settings while pinning the remote path to `/var/www/mojoworks/labs/bank`.
- Added a deployed-version marker so the v0.1.2 → v0.1.3 transition deploys automatically after the updated watcher reloads.

## [0.1.2] - 2026-09-08

### Fixed
- Made `build-watch.sh` own the local demo lifecycle.
- The watcher now starts the demo automatically, restarts it after releases, monitors it for unexpected exit, and stops it on `Ctrl+C`.
- Removed the need to run `scripts/dev.sh` manually.

## [0.1.1] - 2026-09-08

### Fixed
- Prevented ZSH's special `path` parameter from being overwritten during verification.
- Established a predictable macOS/Linux command search path for release scripts.
- Recovery release can be dropped into an already-running v0.1.0 watcher without re-bootstrap.

## [0.1.0] - 2026-09-08

### Added
- Initial Blocks product prototype with Home, Blocks, Shop, Worlds and Profile.
- Demo Send Blocks review flow with balance checks.
- Demo Request Blocks and Add Blocks flows.
- Demo Shop purchase flow and World activation flow.
- Local persistence for prototype activity and purchases.
- Foreground `archive/` release watcher for macOS/ZSH.
- Safe ZIP validation, authoritative repository sync and post-update verification.
- Dependency-free local development server.
- Product-language verification to prevent prohibited speculative/crypto terminology in the web UI.
