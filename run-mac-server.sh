#!/usr/bin/env bash
#
# run-mac-server.sh — build "Xremote Server" for macOS and launch it.
#
# Disables the App Sandbox and uses ad-hoc codesigning so CGEvent posting works
# without an Apple Developer cert. Renames the macOS product to "Xremote Server"
# and makes it a menu-bar-only app (LSUIElement = YES).
#
# Usage:  ./run-mac-server.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/Xremote.xcodeproj"
SCHEME="Xremote"
CONFIG="Debug"
PRODUCT_NAME="Xremote Server"

cd "$PROJECT_DIR"

echo "==> Building '$PRODUCT_NAME' for macOS..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -configuration "$CONFIG" \
  -quiet \
  ENABLE_APP_SANDBOX=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="" \
  DEVELOPMENT_TEAM="" \
  PRODUCT_NAME="$PRODUCT_NAME" \
  INFOPLIST_KEY_LSUIElement=YES \
  INFOPLIST_KEY_CFBundleDisplayName="$PRODUCT_NAME" \
  build

# Resolve the freshly built .app path.
BUILT_DIR=$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR/ {print $2; exit}'
)
APP_PATH="$BUILT_DIR/$PRODUCT_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at $APP_PATH" >&2
  exit 1
fi

# Kill any prior instance and wait briefly for the process to exit before
# relaunching (avoids LaunchServices -600 "already terminating" races).
if pkill -x "$PRODUCT_NAME" >/dev/null 2>&1; then
  for _ in 1 2 3 4 5 6 7 8; do
    pgrep -x "$PRODUCT_NAME" >/dev/null || break
    sleep 0.25
  done
fi

echo "==> Launching $APP_PATH..."
open "$APP_PATH"

# Brief wait, then confirm it's running.
sleep 1
if pgrep -fl "$PRODUCT_NAME" >/dev/null; then
  PID=$(pgrep -f "$PRODUCT_NAME" | head -1)
  echo "$PRODUCT_NAME is running (PID $PID)."
  echo ""
  echo "Look at the menu bar (top-right of screen) for the keyboard icon."
  echo "Click it to see the 6-digit pairing PIN and server status."
  echo ""
  echo "If this is the first run, grant Accessibility permission:"
  echo "  System Settings > Privacy & Security > Accessibility > enable '$PRODUCT_NAME'"
else
  echo "Warning: $PRODUCT_NAME did not appear to start. Check Console.app for errors." >&2
fi
