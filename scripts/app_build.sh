#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/scripts/terminal_style.sh"
cd "$ROOT"
command -v xcodebuild >/dev/null 2>&1 || { pb_error "xcodebuild is required on the macOS development machine."; exit 1; }
pb_section "Building Pride iOS app"
rm -rf "$ROOT/build/ios"
xcodebuild -project PrideBank.xcodeproj -scheme PrideBank -configuration Debug -sdk iphonesimulator -derivedDataPath "$ROOT/build/ios" CODE_SIGNING_ALLOWED=NO build
pb_success "iOS simulator build completed."
