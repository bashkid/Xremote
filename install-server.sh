#!/usr/bin/env bash
#
# install-server.sh — install Xremote Server to /Applications, add a
# terminal alias (`xremote-server`) to ~/.zshrc, and register a
# LaunchAgent that starts the server at login.
#
# Idempotent: safe to re-run after each Mac-side change to refresh the
# installed copy.
#
# Usage:  ./install-server.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/Xremote.xcodeproj"
SCHEME="Xremote"
PRODUCT_NAME="Xremote Server"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/$PRODUCT_NAME.app"
AGENT_LABEL="com.finnova.xremote-server"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
ZSHRC="$HOME/.zshrc"
ALIAS_MARKER="# xremote-server alias (managed by install-server.sh)"

cd "$PROJECT_DIR"

# ---------- 1. Build a Release copy ----------
echo "==> Building $PRODUCT_NAME (Release)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -configuration Release \
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

BUILT_DIR=$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR/ {print $2; exit}'
)
BUILT_APP="$BUILT_DIR/$PRODUCT_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Error: built app not found at $BUILT_APP" >&2
  exit 1
fi

# ---------- 2. Install to /Applications ----------
# Kill any running instance from the old install before copying.
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8; do
  pgrep -x "$PRODUCT_NAME" >/dev/null || break
  sleep 0.25
done

echo "==> Installing to $INSTALLED_APP..."
if [[ -d "$INSTALLED_APP" ]]; then
  rm -rf "$INSTALLED_APP"
fi
cp -R "$BUILT_APP" "$INSTALLED_APP"
echo "    Installed."

# ---------- 3. Add zsh alias ----------
if ! grep -qF "$ALIAS_MARKER" "$ZSHRC" 2>/dev/null; then
  echo "==> Adding 'xremote-server' alias to $ZSHRC..."
  {
    echo ""
    echo "$ALIAS_MARKER"
    echo "alias xremote-server='open \"$INSTALLED_APP\"'"
    echo "alias xremote-server-stop='pkill -x \"$PRODUCT_NAME\" || true'"
  } >> "$ZSHRC"
  echo "    Added."
else
  echo "==> Alias already present in $ZSHRC (skipped)."
fi

# ---------- 4. LaunchAgent for login auto-start ----------
mkdir -p "$HOME/Library/LaunchAgents"
echo "==> Writing LaunchAgent at $AGENT_PLIST..."
cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$INSTALLED_APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF
plutil -lint "$AGENT_PLIST" >/dev/null

# Reload the agent so this session picks up the latest binary too.
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"

echo ""
echo "Done."
echo ""
echo "From now on:"
echo "  • The server starts automatically at login."
echo "  • In a new terminal session run:  xremote-server         (start)"
echo "                                    xremote-server-stop    (stop)"
echo ""
echo "(Open a new shell, or run 'source ~/.zshrc', to pick up the alias now.)"
