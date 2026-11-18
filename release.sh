#!/bin/bash
# Builds Looper for Apple silicon and Intel and publishes both as the GitHub release v<version>.
# Needs macOS 13+ with Xcode or the Command Line Tools, plus the GitHub CLI (`brew install gh`, then `gh auth login`).
#
#   ./release.sh               → build arm64 + x86_64, zip them, publish/update the release v<version>
#   ./release.sh --build-only  → build and zip only, nothing is uploaded
#   ./release.sh --draft       → create the release as a draft (only when it doesn't exist yet)
#   ./release.sh --yes         → don't ask before publishing
#
# The version comes from `static let version` in Sources/Looper/Model/LooperController.swift.
# Output: build/Looper (arm64).app, build/Looper (x86_64).app, build/Looper-<version>-<arch>.zip
set -euo pipefail
cd "$(dirname "$0")"

BUILD_ONLY=0; DRAFT=0; YES=0
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=1 ;;
    --draft)      DRAFT=1 ;;
    --yes|-y)     YES=1 ;;
    -h|--help)    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }

VERSION=$(grep -o 'static let version = "[^"]*"' Sources/Looper/Model/LooperController.swift | cut -d'"' -f2)
[[ -n "$VERSION" ]] || die "Couldn't read the version from LooperController.swift"
TAG="v$VERSION"
echo "▶ Looper $VERSION"

# --- Checks before the (slow) build -----------------------------------------
if [[ $BUILD_ONLY -eq 0 ]]; then
  command -v gh >/dev/null || die "GitHub CLI not found. Install it with: brew install gh && gh auth login"
  gh auth status >/dev/null 2>&1 || die "GitHub CLI isn't signed in. Run: gh auth login"
  [[ -z "$(git status --porcelain)" ]] || die "Uncommitted changes. Commit them first (or use --build-only)."
  git fetch -q origin
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  HEAD_SHA=$(git rev-parse HEAD)
  git merge-base --is-ancestor HEAD "origin/$BRANCH" 2>/dev/null \
    || die "HEAD ($BRANCH) isn't pushed yet. Run: git push"
fi

# --- Build -------------------------------------------------------------------
mkdir -p build
for ARCH in arm64 x86_64; do
  echo "▶ Building $ARCH"
  swift build -c release --arch "$ARCH"
  BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)/Looper"
  lipo -info "$BIN"

  APP="build/Looper ($ARCH).app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Drums"
  cp "$BIN" "$APP/Contents/MacOS/Looper"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  VERSION_STR=$(grep -o 'static let version = "[^"]*"' Sources/Looper/Model/LooperController.swift | cut -d'"' -f2)
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION_STR" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  cp Resources/Drums/*.wav "$APP/Contents/Resources/Drums/"
  codesign --force --sign - "$APP"

  ZIP="build/Looper-$VERSION-$ARCH.zip"
  rm -f "$ZIP"
  # ditto keeps the code signature and extended attributes intact.
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "✅ $ZIP ($(du -h "$ZIP" | cut -f1))"
done

ASSETS=("build/Looper-$VERSION-arm64.zip" "build/Looper-$VERSION-x86_64.zip")

if [[ $BUILD_ONLY -eq 1 ]]; then
  echo "✅ Build only, nothing uploaded."
  exit 0
fi

# --- Publish -----------------------------------------------------------------
if gh release view "$TAG" >/dev/null 2>&1; then
  ACTION="replace the files of the existing release $TAG"
else
  ACTION="create the release $TAG at ${HEAD_SHA:0:7} ($BRANCH)"
fi
if [[ $YES -eq 0 ]]; then
  read -r -p "This will $ACTION. Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || die "Cancelled. The zips are in build/."
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "${ASSETS[@]}" --clobber
else
  NOTES="Looper ${VERSION} for macOS 13+. Download **arm64** for Apple silicon (M1–M4) or **x86_64** for Intel Macs. The apps are ad-hoc signed: on first launch right-click the app and choose Open."
  DRAFT_FLAG=(); [[ $DRAFT -eq 1 ]] && DRAFT_FLAG=(--draft)
  gh release create "$TAG" "${ASSETS[@]}" --target "$HEAD_SHA" \
    --title "Looper ${VERSION}" --notes "$NOTES" ${DRAFT_FLAG[@]+"${DRAFT_FLAG[@]}"}
fi

echo "✅ Released: $(gh release view "$TAG" --json url -q .url)"
