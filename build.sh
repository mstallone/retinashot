#!/bin/zsh
# Local development install: builds RetinaShot.app, signs it with your Apple Development identity
# (so the Screen Recording grant survives rebuilds), installs it to /Applications, hands it Shift-Cmd-4,
# and relaunches it. Releases are built by CI from a tag (see README).
#   ./build.sh            build, install, launch
#   ./build.sh --no-launch
set -euo pipefail
cd "$(dirname "$0")"
APP=/Applications/RetinaShot.app

swift build -c release
Scripts/build-app.sh "$(swift build -c release --show-bin-path)/RetinaShot" .build/RetinaShot.app
rm -rf "$APP" && cp -R .build/RetinaShot.app "$APP"

SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(Apple Development|Developer ID Application)[^"]*"' | head -1 | tr -d '"')"
codesign --force --sign "${SIGN_ID:--}" --identifier cc.stallone.retinashot "$APP"

Scripts/install-shortcuts.sh --quiet
if [[ "${1:-}" != "--no-launch" ]]; then
  pkill -x RetinaShot 2>/dev/null || true
  sleep 0.4
  open -a "$APP"
fi
echo "RetinaShot installed at $APP (signed: ${SIGN_ID:-ad-hoc})"
