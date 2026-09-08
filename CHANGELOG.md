# Changelog

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
