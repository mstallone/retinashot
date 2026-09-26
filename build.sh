#!/bin/zsh
# Local development install: builds RetinaShot.app, signs it with your Apple Development identity
# (so the Screen Recording grant survives rebuilds), installs it to /Applications, hands it Shift-Cmd-4,
# and relaunches it. Releases are built by CI from a tag (see README).
#   ./build.sh            build, install, launch
#   ./build.sh --no-launch
#   ./build.sh --replace  also overwrite a Developer ID (release) copy in /Applications
set -euo pipefail
cd "$(dirname "$0")"
APP=/Applications/RetinaShot.app

if [[ -d "$APP" && "$*" != *--replace* ]] && codesign -dvv "$APP" 2>&1 | grep -q '^Authority=Developer ID Application'; then
  echo "$APP is a release build. Pass --replace to overwrite it with a development build." >&2
  exit 1
fi

swift build -c release
Scripts/build-app.sh "$(swift build -c release --show-bin-path)/RetinaShot" .build/RetinaShot.app
rm -rf "$APP" && cp -R .build/RetinaShot.app "$APP"

SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(Apple Development|Developer ID Application)[^"]*"' | head -1 | tr -d '"')"
codesign --force --sign "${SIGN_ID:--}" --identifier cc.stallone.retinashot "$APP"

Scripts/install-shortcuts.sh --quiet
if [[ "$*" != *--no-launch* ]]; then
  pkill -x RetinaShot 2>/dev/null || true
  sleep 0.4
  open -a "$APP"
fi
echo "RetinaShot installed at $APP (signed: ${SIGN_ID:-ad-hoc})"
