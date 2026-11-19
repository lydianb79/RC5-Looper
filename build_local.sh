#!/bin/bash
# Builds Looper on this Mac: one app for Apple silicon and one for Intel.
#   ./build_local.sh          → build/<version>/Looper (arm64).app and build/<version>/Looper (x86_64).app
#   ./build_local.sh --open   → …and launches the app for this Mac
# Needs Xcode or the Xcode Command Line Tools (xcode-select --install), macOS 13 or later.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(grep -o 'static let version = "[^"]*"' Sources/Looper/Model/LooperController.swift | cut -d'"' -f2)
BUILD_NO=$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)
OUT="build/$VERSION"
mkdir -p "$OUT"

for ARCH in arm64 x86_64; do
  echo "▶︎ Building $ARCH …"
  swift build -c release --arch "$ARCH"
  BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)/Looper"
  APP="$OUT/Looper ($ARCH).app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Drums"
  cp "$BIN" "$APP/Contents/MacOS/Looper"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" "$APP/Contents/Info.plist"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  cp Resources/Drums/*.caf Resources/Drums/manifest.json "$APP/Contents/Resources/Drums/"
  codesign --force --sign - "$APP"      # ad-hoc: keeps the microphone permission between launches
  touch "$APP"
  (cd "$OUT" && rm -f "Looper-$VERSION-$ARCH.zip" && ditto -c -k --keepParent "Looper ($ARCH).app" "Looper-$VERSION-$ARCH.zip")
  echo "✅ $APP"
done

if [[ "${1:-}" == "--open" ]]; then
  HOST=$(uname -m)
  [[ "$HOST" == "arm64" ]] || HOST=x86_64
  open "$OUT/Looper ($HOST).app"
fi
