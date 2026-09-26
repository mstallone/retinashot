#!/bin/zsh
# Hands Shift-Cmd-4 and Ctrl-Shift-Cmd-4 to RetinaShot by turning off the built-in shortcuts
# (System Settings › Keyboard › Keyboard Shortcuts › Screenshots). Idempotent. Undo with ./uninstall.sh.
set -euo pipefail
disable() { # $1 = symbolic hot key id, $2 = modifier mask
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
    "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>52</integer><integer>21</integer><integer>$2</integer></array><key>type</key><string>standard</string></dict></dict>"
}
disable 30 1179648   # Shift-Cmd-4: save picture of selected area as a file
disable 31 1441792   # Ctrl-Shift-Cmd-4: copy picture of selected area to the clipboard
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
[[ "${1:-}" == "--shortcuts-only" ]] || echo "Built-in Shift-Cmd-4 shortcuts disabled."
