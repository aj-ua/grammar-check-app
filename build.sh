#!/usr/bin/env bash
# Builds build/GrammarCheck.app from the Swift package.
#   ./build.sh                         ad-hoc signature (Accessibility must be re-granted after each rebuild)
#   SIGN_ID="GrammarCheck Dev" ./build.sh   stable self-signed identity (permission survives rebuilds)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/GrammarCheck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GrammarCheck" "$APP/Contents/MacOS/GrammarCheck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ID="${SIGN_ID:--}"
codesign --force --sign "$SIGN_ID" --identifier com.andrii.grammarcheck "$APP"

echo "Built $APP (signed with: $SIGN_ID)"
# Refresh Finder/Dock icon cache for this bundle.
touch "$APP"
echo "Run:  open $APP"
