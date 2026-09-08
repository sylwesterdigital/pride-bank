# Changelog

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
