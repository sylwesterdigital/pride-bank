# Pride Bank / Blocks

Version 0.2.0.

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

## v0.2.0 product slice

The first native iOS slice implements the protected first-run journey:

Splash → Welcome → Identity → 6-digit PIN → Locked → PIN unlock → Home / Blocks.

The deployed homepage contains a mobile web demo of the same journey. It intentionally does not expose the Blocks balance until setup and unlock have completed.
