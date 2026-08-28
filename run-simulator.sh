#!/usr/bin/env bash
#
# run-simulator.sh — build Xremote, install on an iPhone Simulator, launch it.
#
# Usage:
#   ./run-simulator.sh                 # uses default simulator (iPhone 17)
#   ./run-simulator.sh "iPhone 17 Pro" # specify a different simulator
#
# Requires: Xcode + command-line tools.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/Xremote.xcodeproj"
SCHEME="Xremote"
BUNDLE_ID="finnova.Xremote"
SIMULATOR="${1:-iPhone 17}"
CONFIG="Debug"

cd "$PROJECT_DIR"

echo "==> Building $SCHEME for '$SIMULATOR'..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -configuration "$CONFIG" \
  -quiet \
  build

# Resolve the freshly built .app path from the build settings.
APP_PATH=$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR/ {print $2; exit}'
)/Xremote.app

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Booting simulator '$SIMULATOR'..."
# `boot` is idempotent if already booted (just prints a warning we ignore).
xcrun simctl boot "$SIMULATOR" >/dev/null 2>&1 || true

# Bring Simulator.app to the foreground.
open -a Simulator

echo "==> Installing $APP_PATH..."
xcrun simctl install "$SIMULATOR" "$APP_PATH"

# Terminate any previously running instance so we always launch fresh.
xcrun simctl terminate "$SIMULATOR" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Launching $BUNDLE_ID..."
xcrun simctl launch "$SIMULATOR" "$BUNDLE_ID"

echo "Done."
