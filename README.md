# RetinaShot

A menu-bar replacement for Shift-Cmd-4 on macOS 27.

**Why it exists.** macOS 27 rewrote `/usr/sbin/screencapture` on ScreenCaptureKit, and its
"selected portion" path saves 1 pixel per point (a 600×400 pt selection becomes a 600×400 px file
tagged 144 dpi) while window and full-screen captures are still 2x. RetinaShot captures the whole
display at native resolution and crops, so selections come out at full Retina resolution again.

**What it does**

- Shift-Cmd-4 (or Ctrl-Shift-Cmd-4): crosshair with live coordinates on every display. Drag to select.
  Space while dragging moves the selection, Shift locks an axis, Option resizes from the center,
  Escape cancels. Pressing Space before dragging switches to Apple's window picker, whose window
  path is unaffected by the bug.
- Saves the file to the Desktop (or the folder set in the Screenshot app's Options) with Apple's
  naming, tags it as a screenshot for Spotlight and Finder, and copies it to the clipboard.
- Slides in a floating thumbnail; click it to open, drag it into another
  app. Honors "Show Floating Thumbnail", file type and window-shadow settings from Apple's Options menu.
- Never activates itself, so the app you are using keeps focus and its window shadows.

**Layout**

    Sources/main.swift        app lifecycle, menu, capture flow, permission dialog
    Sources/Selection.swift   overlay panels and the rubber-band view
    Sources/Capture.swift     ScreenCaptureKit capture, crop, save, clipboard
    Sources/Thumbnail.swift   floating preview
    Sources/HotKeys.swift     Carbon global hot keys
    Sources/Preferences.swift Apple's com.apple.screencapture settings
    Sources/Permission.swift  Screen Recording permission helpers
    Sources/Private.swift     two private calls: background cursor, Spotlight screenshot tags
    Tools/make-icon.swift     renders AppIcon.icns

**Build / install**: `./build.sh` (compiles, signs with your Apple Development identity, installs to
/Applications, disables the built-in shortcut, launches). **Remove**: `./uninstall.sh`.

**Permission.** Every app that reads screen pixels needs Screen Recording; Apple's shortcuts skip it
only because they run inside the system. The app is signed with a stable identity so the grant
persists across rebuilds. If the switch shows on but captures fail, Option-click the menu-bar icon
and choose Reset Screen Recording Permission.

**Once Apple fixes the bug** (check: a fresh Shift-Cmd-4 file should be twice its selection size),
run `./uninstall.sh` to hand the shortcut back.
