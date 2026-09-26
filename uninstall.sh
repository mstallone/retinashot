#!/bin/zsh
# Removes RetinaShot and gives Shift-Cmd-4 back to macOS.
set -euo pipefail
pkill -x RetinaShot 2>/dev/null || true
sleep 0.3
[[ -d /Applications/RetinaShot.app ]] && open -W -a /Applications/RetinaShot.app --args --unregister-login
enable() {
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
    "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>52</integer><integer>21</integer><integer>$2</integer></array><key>type</key><string>standard</string></dict></dict>"
}
enable 30 1179648
enable 31 1441792
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
tccutil reset ScreenCapture cc.stallone.retinashot >/dev/null 2>&1 || true
rm -rf /Applications/RetinaShot.app
echo "RetinaShot removed; built-in Shift-Cmd-4 restored."
