#!/bin/zsh
# Compatibility entry point for v0.1.x watchers.
set -e
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
exec "$ROOT/scripts/verify_repo.sh" "$@"
