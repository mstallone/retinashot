#!/bin/zsh
# Builds RetinaShot.app, installs it to /Applications, replaces the built-in Shift-Cmd-4, and (re)launches it.
#   ./build.sh            build, install, launch
#   ./build.sh --no-launch
set -euo pipefail
cd "$(dirname "$0")"
APP=/Applications/RetinaShot.app
BUILD=.build
FRAMEWORKS=(-framework AppKit -framework ScreenCaptureKit -framework ServiceManagement -framework Carbon
            -F /System/Library/PrivateFrameworks -framework SkyLight)

mkdir -p "$BUILD"
if [[ ! -f "$BUILD/AppIcon.icns" || Tools/make-icon.swift -nt "$BUILD/AppIcon.icns" ]]; then
  swiftc -O Tools/make-icon.swift -o "$BUILD/make-icon"
  rm -rf "$BUILD/AppIcon.iconset"
  "$BUILD/make-icon" "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
fi

swiftc -O Sources/*.swift -o "$BUILD/RetinaShot" "${FRAMEWORKS[@]}"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/RetinaShot" "$APP/Contents/MacOS/RetinaShot"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity keeps the Screen Recording grant valid across rebuilds (ad-hoc signatures change every build).
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(Apple Development|Developer ID Application)[^"]*"' | head -1 | tr -d '"')"
codesign --force --sign "${SIGN_ID:--}" --identifier cc.stallone.retinashot "$APP"

./install.sh --shortcuts-only
if [[ "${1:-}" != "--no-launch" ]]; then
  pkill -x RetinaShot 2>/dev/null || true
  sleep 0.4
  open -a "$APP"
fi
echo "RetinaShot installed at $APP (signed: ${SIGN_ID:-ad-hoc})"
