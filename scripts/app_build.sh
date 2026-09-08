#!/bin/zsh
set -e
set -o pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Pride Bank connected-device build/install/launch.
# This intentionally follows the supplied Shar app_build.sh signing model:
# use the known Xcode account/team explicitly instead of guessing from Keychain.

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/terminal_style.sh"
source "$SCRIPT_DIR/release_profile.sh"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
pb_load_release_profile
API_BASE_URL="${PB_API_BASE_URL:-${PB_REMOTE_URL:+${PB_REMOTE_URL%/}/api/}}"
[[ -n "$API_BASE_URL" ]] || { pb_error "Verified backend deployment did not provide PB_API_BASE_URL. The watcher should obtain this automatically from deploy_backend.sh; refusing to build an app pointed at an unknown service."; exit 1; }
[[ "$API_BASE_URL" == https://* ]] || { pb_error "Pride API URL must use HTTPS: $API_BASE_URL"; exit 1; }

PROJECT="$ROOT/PrideBank.xcodeproj"
SCHEME="PrideBank"
CONFIGURATION="Debug"
DERIVED_DATA="$ROOT/build/DerivedData"
LOG_DIR="$ROOT/build/logs"
BUILD_LOG="$LOG_DIR/app_build.log"
INSTALL_LOG="$LOG_DIR/app_install.log"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/PrideBank.app"

# Same default team as the user-supplied Shar workflow. Never auto-pick a random
# certificate/team from Keychain: that is what caused v0.2.1 "No Account for Team".
TEAM_ID="${TEAM_ID:-${PRIDE_APPLE_TEAM_ID:-${PB_DEVELOPMENT_TEAM:-5P9V78UZAC}}}"
DEVICE_ID="${DEVICE_ID:-${PB_IOS_DEVICE_ID:-}}"
BUNDLE_ID="${BUNDLE_ID:-${PRIDE_BUNDLE_ID:-}}"

fail(){ pb_error "$*"; exit 1; }

# Prefer full Xcode even if xcode-select points at CommandLineTools.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  else
    SELECTED="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$SELECTED" == *".app/Contents/Developer"* ]]; then
      export DEVELOPER_DIR="$SELECTED"
    fi
  fi
fi

for tool in xcodebuild xcrun python3 codesign; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required on the macOS development machine."
done
[[ "$(uname -s)" == Darwin ]] || fail "iOS build/deploy must run on macOS."
[[ -d "$PROJECT" ]] || fail "Project not found: $PROJECT"

mkdir -p "$LOG_DIR"
: > "$BUILD_LOG"

pb_section "Xcode"
xcodebuild -version
pb_field "Developer dir:" "${DEVELOPER_DIR:-$(xcode-select -p)}"

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  pb_section "Completing Xcode first-launch setup"
  xcodebuild -runFirstLaunch || fail "Xcode first-launch setup could not complete. Open Xcode once if macOS requires administrator/license confirmation."
fi
export IDEPreferLogStreaming=YES

[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "Invalid Apple development TEAM_ID: $TEAM_ID"
if [[ -z "$BUNDLE_ID" ]]; then
  TEAM_LOWER="$(printf '%s' "$TEAM_ID" | tr '[:upper:]' '[:lower:]')"
  BUNDLE_ID="xyz.mojoworks.pridebank.${TEAM_LOWER}"
fi
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || fail "Invalid bundle identifier: $BUNDLE_ID"

pb_section "Signing"
pb_field "Team:" "$TEAM_ID"
pb_field "Bundle ID:" "$BUNDLE_ID"
pb_field "Mode:" "Automatic signing + provisioning updates"

pb_section "Detecting connected iOS device"
DEVICE_JSON="$(mktemp -t pride-bank-devices)"
DEVICE_ROWS="$(mktemp -t pride-bank-device-rows)"
trap 'rm -f "$DEVICE_JSON" "$DEVICE_ROWS"' EXIT INT TERM

xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null \
  || fail "devicectl could not enumerate devices."

python3 - "$DEVICE_JSON" > "$DEVICE_ROWS" <<'PYDEV'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data=json.load(f)
rows=[]
for d in data.get('result', {}).get('devices', []):
    old_hw=d.get('hardwareProperties') or {}
    old_dev=d.get('deviceProperties') or {}
    old_conn=d.get('connectionProperties') or {}
    props=d.get('properties') or {}
    hw=props.get('hardware') or {}
    state=props.get('state') or {}
    conn=props.get('connection') or {}
    reality=(old_hw.get('reality') or hw.get('reality') or '').lower()
    platform=(old_hw.get('platform') or hw.get('platform') or '').lower()
    dtype=(old_hw.get('deviceType') or hw.get('deviceType') or '').lower()
    name=old_dev.get('name') or props.get('name') or state.get('name') or 'iOS device'
    model=old_hw.get('marketingName') or hw.get('marketingName') or old_hw.get('modelName') or hw.get('modelName') or ''
    osver=old_dev.get('osVersionNumber') or state.get('osVersionNumber') or old_dev.get('osVersion') or state.get('osVersion') or ''
    udid=old_hw.get('udid') or hw.get('udid') or d.get('udid') or ''
    core_id=d.get('identifier') or ''
    tunnel=(old_conn.get('tunnelState') or conn.get('tunnelState') or conn.get('state') or '').lower()
    pairing=(old_conn.get('pairingState') or conn.get('pairingState') or '').lower()
    transport=(old_conn.get('transportType') or conn.get('transportType') or '').lower()
    devmode=(old_dev.get('developerModeStatus') or state.get('developerModeStatus') or props.get('developerModeStatus') or '').lower()
    boot=(old_dev.get('bootState') or state.get('bootState') or '').lower()
    is_ios=('ios' in platform or 'iphone' in platform or dtype in ('iphone','ipad'))
    if not platform and not dtype:
        is_ios=bool(udid)
    physical=reality in ('','physical') and is_ios
    online=tunnel in ('connected','available') or (pairing=='paired' and transport in ('wired','usb','localnetwork','network')) or boot=='booted'
    ident=udid or core_id
    if physical and online and ident:
        clean=lambda v: str(v or '').replace('\t',' ').replace('\n',' ')
        rows.append((clean(ident),clean(name),clean(model),clean(osver),clean(devmode)))
for row in rows:
    print('\t'.join(row))
PYDEV

if [[ -z "$DEVICE_ID" ]]; then
  COUNT="$(wc -l < "$DEVICE_ROWS" | tr -d ' ')"
  if [[ "$COUNT" == "0" ]]; then
    pb_warn "No connected physical iPhone/iPad is available to CoreDevice. Running unsigned generic iOS compile only."
    rm -rf "$DERIVED_DATA"
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      build
    pb_success "Generic iOS compile passed; no device install was attempted."
    exit 20
  elif [[ "$COUNT" != "1" ]]; then
    pb_error "More than one connected physical iPhone/iPad is available. Refusing to guess."
    awk -F '\t' '{printf "  - %s (%s)\n", $2, $1}' "$DEVICE_ROWS" >&2
    printf 'Set DEVICE_ID (or PB_IOS_DEVICE_ID) before starting the watcher.\n' >&2
    exit 1
  fi
  FIRST_DEVICE="$(head -n 1 "$DEVICE_ROWS")"
  IFS=$'\t' read -r DEVICE_ID DEVICE_NAME DEVICE_MODEL DEVICE_OS DEVICE_DEVMODE <<< "$FIRST_DEVICE"
else
  MATCHED="$(awk -F '\t' -v id="$DEVICE_ID" '$1 == id {print; exit}' "$DEVICE_ROWS")"
  [[ -n "$MATCHED" ]] || fail "Requested iOS DEVICE_ID is not currently connected: $DEVICE_ID"
  IFS=$'\t' read -r _ DEVICE_NAME DEVICE_MODEL DEVICE_OS DEVICE_DEVMODE <<< "$MATCHED"
fi

if [[ "$DEVICE_DEVMODE" == "disabled" ]]; then
  fail "Developer Mode is disabled on $DEVICE_NAME. Enable it on the iPhone before development apps can launch."
fi

pb_field "Device:" "$DEVICE_NAME"
[[ -n "$DEVICE_MODEL" ]] && pb_field "Model:" "$DEVICE_MODEL"
[[ -n "$DEVICE_OS" ]] && pb_field "iOS:" "$DEVICE_OS"
pb_field "ID:" "$DEVICE_ID"

pb_section "Building and signing Pride Bank"
rm -rf "$DERIVED_DATA"
mkdir -p "$DERIVED_DATA"
set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  PRIDE_API_BASE_URL="$API_BASE_URL" \
  clean build > >(tee "$BUILD_LOG") 2>&1
BUILD_STATUS=$?
set -e
if (( BUILD_STATUS != 0 )); then
  printf '\nBuild log: %s\n' "$BUILD_LOG" >&2
  if grep -Fq 'No Account for Team' "$BUILD_LOG"; then
    fail "Xcode has no signed-in account for team $TEAM_ID. The supplied Shar workflow expects this team to be available in Xcode Accounts."
  fi
  if grep -Fq 'No profiles for' "$BUILD_LOG"; then
    fail "Xcode could not create/find a development provisioning profile for $BUNDLE_ID under team $TEAM_ID."
  fi
  fail "xcodebuild failed. The complete signing/build error is in the log above."
fi

[[ -d "$APP_PATH" ]] || fail "Build succeeded but app bundle was not found at $APP_PATH"

pb_section "Verifying signed app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ "$ACTUAL_BUNDLE_ID" == "$BUNDLE_ID" ]] || fail "Built bundle identifier '$ACTUAL_BUNDLE_ID' does not match '$BUNDLE_ID'."

BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ -n "$BUNDLE_EXECUTABLE" ]] || fail "Built app Info.plist is missing CFBundleExecutable; refusing device installation."
[[ "$BUNDLE_EXECUTABLE" != *'/'* ]] || fail "Built app CFBundleExecutable is invalid: $BUNDLE_EXECUTABLE"
[[ -f "$APP_PATH/$BUNDLE_EXECUTABLE" ]] || fail "CFBundleExecutable points to a missing file: $APP_PATH/$BUNDLE_EXECUTABLE"
[[ -x "$APP_PATH/$BUNDLE_EXECUTABLE" ]] || fail "CFBundleExecutable is not executable: $APP_PATH/$BUNDLE_EXECUTABLE"
pb_field "Executable:" "$BUNDLE_EXECUTABLE"

pb_section "Installing Pride Bank on $DEVICE_NAME"
: > "$INSTALL_LOG"
set +e
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" > "$INSTALL_LOG" 2>&1
INSTALL_STATUS=$?
set -e
cat "$INSTALL_LOG"
if (( INSTALL_STATUS != 0 )); then
  printf '\nInstall log: %s\n' "$INSTALL_LOG" >&2
  fail "devicectl could not install the signed app on $DEVICE_NAME."
fi

pb_section "Launching Pride Bank on $DEVICE_NAME"
if xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID"; then
  pb_success "Pride Bank launched on $DEVICE_NAME."
else
  pb_warn "Pride Bank installed successfully but iOS refused automatic launch. The release will continue because installation succeeded."
fi

pb_banner_success "PRIDE iOS APP DEPLOYED"
pb_field "Device:" "$DEVICE_NAME"
pb_field "Bundle:" "$BUNDLE_ID"
pb_field "App:" "$APP_PATH"
