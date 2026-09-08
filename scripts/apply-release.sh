#!/bin/zsh
echo "apply-release.sh is deprecated; build-watch.sh synchronises authoritative releases and then uses scripts/deploy.sh."
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
exec "$SCRIPT_DIR/deploy.sh" "$@"
