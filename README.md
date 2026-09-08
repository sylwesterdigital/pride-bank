# Pride Bank / Blocks prototype

Current release: **v0.1.3**

## Release workflow

The foreground watcher is the only command required on the Mac:

```zsh
./scripts/build-watch.sh
```

While it is running it:

- watches `archive/` for `pride-bank-v*.zip`;
- waits until a ZIP is stable before touching it;
- validates and applies the complete source release;
- runs repository/product verification;
- reloads itself when watcher code changes;
- runs `scripts/deploy.sh` for every source version not yet deployed;
- commits/pushes the release source to `main`;
- deploys the web surface to `/var/www/mojoworks/labs/bank`;
- returns to watching for the next ZIP.

There is no local demo server and no second development command in the release workflow.

## Deployment profile

Private SSH details stay outside Git at:

```text
~/.config/workwork/pride-bank-release.env
```

On first use, `scripts/release_profile.sh` can import the existing Rantlist or Shar release SSH profile and pins the Pride Bank remote directory to:

```text
/var/www/mojoworks/labs/bank
```

## Release delivery

Drop newer releases into:

```text
archive/
```

The directory is intentionally Git ignored.

## Product direction

Blocks is an internal creative-platform economy. User-facing language avoids crypto, trading and speculative-finance framing.
