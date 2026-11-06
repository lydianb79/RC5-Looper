#!/bin/bash
# Builds Looper.app from the Swift package (needs Xcode or the Xcode Command Line Tools, macOS 13+).
#   ./build_app.sh            → build/Looper.app (release)
#   ./build_app.sh debug      → debug build
#   ./build_app.sh release --open   → build and launch
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Looper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Looper" "$APP/Contents/MacOS/Looper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS keeps the microphone permission between launches.
codesign --force --sign - "$APP"

touch "$APP"   # refresh Finder / Dock icon cache
echo "✅ Built $APP"
if [[ "${2:-}" == "--open" ]]; then open "$APP"; fi
