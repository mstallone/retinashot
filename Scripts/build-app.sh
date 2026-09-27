#!/bin/bash
# Stages RetinaShot.app from a built binary. Used by build.sh (local) and build-release.sh (CI).
#   Scripts/build-app.sh <binary> <output.app> [version]
# The version defaults to the nearest tag; CFBundleVersion is always the commit count.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:?path to the built RetinaShot binary}"
APP="${2:?output .app path}"
VERSION="${3:-$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
ICON="$ROOT/.build/AppIcon.icns"

if [[ ! -f "$ICON" || "$ROOT/Tools/make-icon.swift" -nt "$ICON" ]]; then
  mkdir -p "$ROOT/.build"
  swiftc -O "$ROOT/Tools/make-icon.swift" -o "$ROOT/.build/make-icon"
  rm -rf "$ROOT/.build/AppIcon.iconset"
  "$ROOT/.build/make-icon" "$ROOT/.build/AppIcon.iconset"
  iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM stamps the deployment target as the SDK version. AppKit keys modern control and alert styling off
# that stamp, so restamp it with the SDK actually used. The minimum is macOS 27, the only release with the
# bug; the package targets 26 so CI's Xcode 26 SDK can build it.
SDK="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos 27.0 "$SDK" -replace -output "$APP/Contents/MacOS/RetinaShot" "$BINARY"
chmod +x "$APP/Contents/MacOS/RetinaShot"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/Resources/Info.plist" >"$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
echo "staged $APP ($VERSION, build $BUILD)"
