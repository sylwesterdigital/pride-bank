# Pride Bank / Blocks

Version 0.2.4.

A mobile-first internal creative economy. Blocks are internal units members can use across the service to send, request, add, buy creative products and participate in Worlds.

## Release workflow

The foreground watcher is the single local command:

```zsh
./scripts/build-watch.sh
```

Drop a complete release ZIP named `pride-bank-vX.Y.Z.zip` into `archive/`. The watcher follows the Shar-style flow: wait for a stable ZIP, validate it, synchronise the repository authoritatively, verify/build, commit/push, deploy the homepage to the configured Ubuntu target, verify deployment, then continue watching.

The server target is pinned to:

```text
/var/www/mojoworks/labs/bank
```

## Product slice

The first native iOS slice implements the protected first-run journey:

Splash → Welcome → Identity → 6-digit PIN → Locked → PIN unlock → Home / Blocks.

The deployed homepage contains a mobile web demo of the same journey. It intentionally does not expose the Blocks balance until setup and unlock have completed.

## Brand

`brand/pride-bank.svg` is the canonical Pride mark. The native iOS app icon and in-app imagery, plus the hosted web favicon, splash, onboarding and header branding, are derived from that supplied source. Product code must not introduce a replacement geometric/block logo.

## Physical iOS deployment

The foreground `scripts/build-watch.sh` owns mobile deployment. After a release ZIP is applied and verified, the release pipeline enumerates Xcode devices. If exactly one trusted physical iOS device is available it builds `PrideBank` for that device, signs it using the configured Apple development team, installs the `.app`, launches `xyz.mojoworks.pridebank`, then continues the normal Git and Ubuntu deployment flow.

If no physical device is connected, the release performs a simulator compile check and continues. If a physical device is present but unavailable, or multiple devices are available without an explicit `PB_IOS_DEVICE_ID`, the release stops instead of silently deploying to the wrong place.
