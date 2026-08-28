#!/usr/bin/env bash
#
# run-iphone.sh — build Xremote and install on a connected iPhone.
#
# Usage:  ./run-iphone.sh
#
# Builds for "any iOS device" (no need to match the device name) and
# installs on the first connected iPhone via devicectl.
#
# Requires:
#   - iPhone plugged in via USB, unlocked, Developer Mode enabled
#   - Apple Development cert in login keychain (codesign ACL granted)
#   - Developer profile trusted on the device (first install only)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/Xremote.xcodeproj"
SCHEME="Xremote"
BUNDLE_ID="finnova.Xremote"
CONFIG="Debug"

cd "$PROJECT_DIR"

# Find the first connected iPhone. We pull the UUID out of devicectl's
# columnar output by matching the canonical 8-4-4-4-12 UUID format.
DEVICE_LINE=$(
  xcrun devicectl list devices 2>/dev/null \
    | awk 'NR>2 && /iPhone/ && !/^-/ {print; exit}'
)
if [[ -z "$DEVICE_LINE" ]]; then
  echo "Error: no iPhone is connected." >&2
  echo "Plug in your iPhone via USB, unlock it, trust the computer, then retry." >&2
  exit 1
fi

DEVICE_ID=$(
  echo "$DEVICE_LINE" \
    | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    | head -1
)
if [[ -z "$DEVICE_ID" ]]; then
  echo "Error: could not parse device UUID from devicectl output." >&2
  xcrun devicectl list devices
  exit 1
fi

echo "==> Target device: $DEVICE_ID"

echo "==> Building for any iOS device..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration "$CONFIG" \
  -allowProvisioningUpdates \
  -quiet \
  build

# Resolve the freshly built .app path.
BUILT_DIR=$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR/ {print $2; exit}'
)
APP_PATH="$BUILT_DIR/Xremote.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Installing $APP_PATH..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >/dev/null
echo "    Installed."

echo "==> Launching $BUNDLE_ID..."
if xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1 | grep -q "Locked"; then
  echo "    Phone is locked. Unlock it and tap the Xremote icon to launch."
elif xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "    Launched."
else
  echo "    Launch failed — common reasons:"
  echo "      • First install: trust the developer profile in"
  echo "        Settings > General > VPN & Device Management."
fi

echo "Done."
