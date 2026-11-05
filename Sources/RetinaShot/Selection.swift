import AppKit
import Carbon.HIToolbox

/// The rubber-band selection: one transparent, non-activating panel per display, so the app you are using
/// keeps focus. Mirrors the built-in tool: crosshair with coordinates, size badge while dragging,
/// Space while dragging moves the selection, Shift locks an axis, Option resizes from the center.
@MainActor
final class SelectionSession {
    enum Outcome { case selected(CGRect, on: NSScreen), window, cancelled }

    private let hotKeys: HotKeys
    private let completion: (Outcome) -> Void
    private var panels: [OverlayPanel] = []
    private var keys: [UInt32] = []
    private var tap: MouseTap?
    private var finished = false

    /// Fails when the mouse can't be tapped, which needs Accessibility.
    init?(hotKeys: HotKeys, completion: @escaping (Outcome) -> Void) {
        self.hotKeys = hotKeys
        self.completion = completion
        guard let tap = MouseTap(handler: { [weak self] type, event in self?.route(type, event) }) else { return nil }
        self.tap = tap
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            panel.selectionView.onFinish = { [weak self, unowned panel] rect in
                self?.finish(rect.map { .selected(Self.globalRect(panel.convertToScreen($0)), on: panel.display) } ?? .cancelled)
            }
            panels.append(panel)
        }
        panels.forEach { $0.orderFrontRegardless() }
        keys = [
            hotKeys.register(kVK_Escape) { [weak self] pressed in if pressed { self?.finish(.cancelled) } },
            hotKeys.register(kVK_Space) { [weak self] pressed in self?.space(pressed) },
        ]
        // The pointer resets as the panels appear, so assert the crosshair over the first moments.
        for delay in [0, 0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.finished else { return }
                let mouse = NSEvent.mouseLocation
                (self.panels.first { $0.frame.contains(mouse) } ?? self.panels.first)?.selectionView.refreshCursor()
            }
        }
    }

    /// Shows each display as it was frozen, under the selection.
    func showFrozen(_ images: [CGDirectDisplayID: CGImage]) {
        for panel in panels {
            if let id = panel.display.displayID, let image = images[id] { panel.showFrozen(image) }
        }
    }

    private func space(_ pressed: Bool) {
        if let dragging = panels.first(where: { $0.selectionView.isDragging }) {
            dragging.selectionView.isMoving = pressed
        } else if pressed {
            finish(.window)
        }
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        keys.forEach(hotKeys.unregister)
        tap?.stop()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        setCursorInBackground(.arrow)
        completion(outcome)
    }

    /// Hands a mouse event from the tap to the panel being dragged on, or else the one under the pointer.
    private func route(_ type: CGEventType, _ event: CGEvent) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screenPoint = NSPoint(x: event.location.x, y: primaryHeight - event.location.y)
        guard let panel = panels.first(where: { $0.selectionView.isDragging }) ?? panels.first(where: { NSMouseInRect(screenPoint, $0.frame, false) })
        else { return }
        let view = panel.selectionView
        let point = view.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        switch type {
        case .mouseMoved: view.move(to: point)
        case .leftMouseDown: view.press(at: point)
        case .leftMouseDragged: view.drag(to: point, shift: event.flags.contains(.maskShift))
        case .leftMouseUp: view.release(at: point)
        default: break
        }
    }

    /// AppKit screen coordinates (origin bottom-left, y up) → CoreGraphics global (origin top-left, y down).
    private static func globalRect(_ r: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

final class OverlayPanel: NSPanel {
    let selectionView: SelectionView
    let display: NSScreen

    init(screen: NSScreen) {
        display = screen
        selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor(white: 0, alpha: 0.01) // non-zero so a click the tap misses lands on the panel, not the app beneath
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let content = NSView(frame: selectionView.frame)
        content.wantsLayer = true
        selectionView.autoresizingMask = [.width, .height]
        content.addSubview(selectionView)
        contentView = content
    }

    func showFrozen(_ image: CGImage) {
        contentView?.layer?.contents = image
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
}

final class SelectionView: NSView {
    var onFinish: ((NSRect?) -> Void)?
    private(set) var isDragging = false
    var isMoving = false

    private enum AxisLock { case width(ClosedRange<CGFloat>), height(ClosedRange<CGFloat>) }
    private var anchor: NSPoint?   // fixed corner, or the center while Option is held
    private var cursor: NSPoint?
    private var axisLock: AxisLock?
    private var lastDrawn = NSRect.zero
    private let badgeAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]

    override var isOpaque: Bool { false }

    // MARK: Mouse

    // Fed by the session's `MouseTap`.
    func move(to point: NSPoint) { cursor = point; redraw() }

    func press(at point: NSPoint) {
        isDragging = true
        anchor = point
        move(to: point)
    }

    func drag(to point: NSPoint, shift: Bool) {
        if isMoving, let a = anchor, let c = cursor {
            anchor = NSPoint(x: a.x + point.x - c.x, y: a.y + point.y - c.y)
        }
        cursor = point
        updateAxisLock(shift: shift)
        redraw()
    }

    func release(at point: NSPoint) {
        move(to: point)
        let rect = selection
        isDragging = false
        isMoving = false
        anchor = nil
        axisLock = nil
        redraw()
        onFinish?(rect.flatMap { $0.width >= 2 && $0.height >= 2 ? $0 : nil })
    }

    /// Shows the crosshair and badge for wherever the pointer is right now, without waiting for it to move.
    func refreshCursor() {
        guard let window = window else { return }
        cursor = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        redraw()
    }

    // MARK: Geometry

    var selection: NSRect? {
        guard let a = anchor, let c = cursor else { return nil }
        let dx = abs(c.x - a.x), dy = abs(c.y - a.y)
        var r = NSEvent.modifierFlags.contains(.option)
            ? NSRect(x: a.x - dx, y: a.y - dy, width: 2 * dx, height: 2 * dy)
            : NSRect(x: min(a.x, c.x), y: min(a.y, c.y), width: dx, height: dy)
        switch axisLock {
        case .width(let span): r.origin.x = span.lowerBound; r.size.width = span.upperBound - span.lowerBound
        case .height(let span): r.origin.y = span.lowerBound; r.size.height = span.upperBound - span.lowerBound
        case nil: break
        }
        return r.integral
    }

    /// Shift freezes whichever dimension the pointer is not moving along, decided when Shift goes down.
    private func updateAxisLock(shift: Bool) {
        guard shift else { axisLock = nil; return }
        guard axisLock == nil, let r = selection, let a = anchor, let c = cursor else { return }
        axisLock = abs(c.x - a.x) >= abs(c.y - a.y) ? .height(r.minY...r.maxY) : .width(r.minX...r.maxX)
    }

    // MARK: Cursor

    /// The badge rides inside the cursor image, so the window server moves it in lockstep with the
    /// crosshair instead of the app redrawing it a frame behind. Near an edge it flips to the other side.
    /// Idle it shows the pointer's coordinates (from the display's top-left, like Apple); dragging, the size.
    private func updateCursor() {
        guard let c = cursor else { return }
        let base = NSCursor.crosshair
        let text = selection.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "\(Int(c.x)), \(Int(bounds.height - c.y))"
        let textSize = (text as NSString).size(withAttributes: badgeAttributes)
        let badge = NSSize(width: (textSize.width + 12).rounded(.up), height: (textSize.height + 6).rounded(.up))
        let gap: CGFloat = 10
        let toRight = c.x + gap + badge.width <= bounds.maxX - 4
        let toBelow = c.y - gap - badge.height >= 4

        // Laid out in flipped (top-left origin) coordinates around the hot spot, as cursor images are.
        let hot = base.hotSpot, baseSize = base.image.size
        let crosshairRect = NSRect(x: -hot.x, y: -hot.y, width: baseSize.width, height: baseSize.height)
        let badgeRect = NSRect(x: toRight ? gap : -gap - badge.width, y: toBelow ? gap : -gap - badge.height,
                               width: badge.width, height: badge.height)
        let canvas = crosshairRect.union(badgeRect)
        let attributes = badgeAttributes
        let image = NSImage(size: canvas.size, flipped: true) { _ in
            let shift = CGAffineTransform(translationX: -canvas.minX, y: -canvas.minY)
            base.image.draw(in: crosshairRect.applying(shift), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let box = badgeRect.applying(shift)
            NSColor(white: 0.1, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
            (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
            return true
        }
        setCursorInBackground(NSCursor(image: image, hotSpot: NSPoint(x: -canvas.minX, y: -canvas.minY)))
    }

    // MARK: Drawing

    /// Update the cursor, and invalidate only what was drawn last time and what will be drawn now.
    private func redraw() {
        updateCursor()
        let next = selection?.insetBy(dx: -2, dy: -2) ?? .zero
        setNeedsDisplay(lastDrawn.union(next))
        lastDrawn = next
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let r = selection else { return }
        NSColor(white: 1, alpha: 0.10).setFill()
        r.fill()
        NSColor(white: 0, alpha: 0.55).setStroke()
        NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

/// While a selection is on screen, takes the mouse before any app sees it. The app you were using stays
/// active and would otherwise get every move and set its own cursor (arrow, pointing hand) over the
/// crosshair, and windows the system keeps above the panels, such as crash and permission alerts, would get
/// the clicks. Other buttons are taken too, and ignored. Needs Accessibility.
@MainActor
final class MouseTap {
    private var port: CFMachPort?
    private let handler: (CGEventType, CGEvent) -> Void

    init?(handler: @escaping (CGEventType, CGEvent) -> Void) {
        self.handler = handler
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp,
                                    .otherMouseDown, .otherMouseDragged, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, info in
            let consumed = MainActor.assumeIsolated {
                let tap = Unmanaged<MouseTap>.fromOpaque(info!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = tap.port { CGEvent.tapEnable(tap: port, enable: true) }
                    return false
                }
                tap.handler(type, event)
                return true
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        self.port = nil
    }
}
