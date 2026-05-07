#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ClaudeUsageBar"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BIN_PATH=".build/release/$APP_NAME"

echo "==> Building $APP_NAME (release)…"
swift build -c release

if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: expected binary at $BIN_PATH was not produced." >&2
    exit 1
fi

echo "==> Assembling $APP_NAME.app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign so macOS will accept Keychain prompts and notifications. Real distribution would
# need a Developer ID; ad-hoc is enough for personal use.
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo
echo "==> Done."
echo "    App bundle: $APP_BUNDLE"
echo
echo "Next steps:"
echo "  1. Drag $APP_NAME.app to /Applications."
echo "  2. Launch it once. macOS will ask for Keychain access ('Claude Safe Storage')."
echo "     Click 'Always Allow'."
echo "  3. Optional: add to login items in"
echo "     System Settings → General → Login Items."
