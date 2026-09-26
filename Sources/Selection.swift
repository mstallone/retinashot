import AppKit
import Carbon.HIToolbox

/// The rubber-band selection: one transparent, non-activating panel per display, so the app you are using
/// keeps focus. Mirrors the built-in tool: crosshair with coordinates, size badge while dragging,
/// Space while dragging moves the selection, Shift locks an axis, Option resizes from the center.
@MainActor
final class SelectionSession {
    enum Outcome { case selected(CGRect), window, cancelled }

    private let hotKeys: HotKeys
    private let completion: (Outcome) -> Void
    private var panels: [OverlayPanel] = []
    private var keys: [UInt32] = []
    private var finished = false

    init(hotKeys: HotKeys, completion: @escaping (Outcome) -> Void) {
        self.hotKeys = hotKeys
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            panel.selectionView.onFinish = { [weak self, unowned panel] rect in
                self?.finish(rect.map { .selected(Self.globalRect(panel.convertToScreen($0))) } ?? .cancelled)
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
                if self?.finished == false { showCrosshairInBackground() }
            }
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
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.arrow.set()
        completion(outcome)
    }

    /// AppKit screen coordinates (origin bottom-left, y up) → CoreGraphics global (origin top-left, y down).
    private static func globalRect(_ r: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

final class OverlayPanel: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor(white: 0, alpha: 0.01) // non-zero so every point of the panel receives clicks
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = selectionView
    }
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
    private let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) { showCrosshairInBackground() }
    override func mouseEntered(with event: NSEvent) { showCrosshairInBackground(); track(event) }
    override func mouseExited(with event: NSEvent) { if !isDragging { cursor = nil; redraw() } }
    override func mouseMoved(with event: NSEvent) { showCrosshairInBackground(); track(event) }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        anchor = location(event)
        track(event)
    }

    override func mouseDragged(with event: NSEvent) {
        showCrosshairInBackground()
        let point = location(event)
        if isMoving, let a = anchor, let c = cursor {
            anchor = NSPoint(x: a.x + point.x - c.x, y: a.y + point.y - c.y)
        }
        cursor = point
        updateAxisLock(shift: event.modifierFlags.contains(.shift))
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        track(event)
        let rect = selection
        isDragging = false
        isMoving = false
        anchor = nil
        axisLock = nil
        redraw()
        onFinish?(rect.flatMap { $0.width >= 2 && $0.height >= 2 ? $0 : nil })
    }

    private func location(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }
    private func track(_ event: NSEvent) { cursor = location(event); redraw() }

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

    // MARK: Drawing

    /// The size badge while dragging, otherwise the pointer's coordinates (from the display's top-left, like Apple).
    private var badge: (text: NSString, box: NSRect)? {
        let text: NSString
        let anchor: NSPoint
        if let r = selection {
            text = "\(Int(r.width)) × \(Int(r.height))" as NSString
            anchor = NSPoint(x: r.maxX - 4, y: r.minY - 4)
        } else if let c = cursor {
            text = "\(Int(c.x)), \(Int(bounds.height - c.y))" as NSString
            anchor = NSPoint(x: c.x + 10, y: c.y - 10) // just clear of the crosshair's arms
        } else {
            return nil
        }
        let size = text.size(withAttributes: badgeAttributes)
        var box = NSRect(x: selection == nil ? anchor.x : anchor.x - size.width - 12,
                         y: anchor.y - size.height - 6, width: size.width + 12, height: size.height + 6)
        box.origin.x = min(max(box.minX, 4), bounds.maxX - 4 - box.width)
        if box.minY < 4 { box.origin.y = anchor.y + 10 }
        return (text, box)
    }

    private var badgeAttributes: [NSAttributedString.Key: Any] { [.font: badgeFont, .foregroundColor: NSColor.white] }

    /// Invalidate only what was drawn last time and what will be drawn now.
    private func redraw() {
        var next = NSRect.zero
        if let r = selection { next = next.union(r.insetBy(dx: -2, dy: -2)) }
        if let b = badge { next = next.union(b.box) }
        setNeedsDisplay(lastDrawn.union(next))
        lastDrawn = next
    }

    override func draw(_ dirtyRect: NSRect) {
        if let r = selection {
            NSColor(white: 1, alpha: 0.10).setFill()
            r.fill()
            NSColor(white: 0, alpha: 0.55).setStroke()
            NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)).stroke()
            NSColor.white.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        if let b = badge {
            NSColor(white: 0.1, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: b.box, xRadius: 5, yRadius: 5).fill()
            b.text.draw(at: NSPoint(x: b.box.minX + 6, y: b.box.minY + 3), withAttributes: badgeAttributes)
        }
    }
}
