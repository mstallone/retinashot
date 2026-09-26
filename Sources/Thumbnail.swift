import AppKit

/// The floating preview that slides in at the bottom-right after a capture, like the built-in one.
/// Click opens the file, drag carries it into another app, hovering keeps it around.
final class ThumbnailPanel: NSPanel {
    private static let maxSize = NSSize(width: 220, height: 150)
    private static let margin: CGFloat = 16
    private static let lifetime: TimeInterval = 5
    private let restingOrigin: NSPoint
    private var dismissal: DispatchWorkItem?

    init(_ shot: Screenshot, on screen: NSScreen) {
        let fit = min(Self.maxSize.width / shot.image.size.width, Self.maxSize.height / shot.image.size.height, 1)
        let size = NSSize(width: max(shot.image.size.width * fit, 1).rounded(), height: max(shot.image.size.height * fit, 1).rounded())
        let visible = screen.visibleFrame
        restingOrigin = NSPoint(x: visible.maxX - size.width - Self.margin, y: visible.minY + Self.margin)
        let offscreen = NSPoint(x: visible.maxX + 8, y: restingOrigin.y)
        super.init(contentRect: NSRect(origin: offscreen, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none

        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size), shot: shot)
        view.onOpen = { [weak self] in
            NSWorkspace.shared.open(shot.url)
            self?.dismiss()
        }
        view.onHover = { [weak self] hovering in
            if hovering { self?.dismissal?.cancel() } else { self?.scheduleDismissal(after: 1.5) }
        }
        contentView = view
    }

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrameOrigin(restingOrigin)
        }
        scheduleDismissal(after: Self.lifetime)
    }

    func dismiss() {
        dismissal?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrameOrigin(NSPoint(x: frame.minX + 24, y: frame.minY))
        }, completionHandler: { [weak self] in self?.orderOut(nil) })
    }

    private func scheduleDismissal(after seconds: TimeInterval) {
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

private final class ThumbnailView: NSView, NSDraggingSource {
    var onOpen: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let shot: Screenshot
    private var pressOrigin: NSPoint?
    private var dragged = false

    init(frame: NSRect, shot: Screenshot) {
        self.shot = shot
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = shot.image
        layer?.contentsGravity = .resizeAspect
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.white.cgColor
    }
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
        dragged = false
    }
    override func mouseUp(with event: NSEvent) { if !dragged { onOpen?() } }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin, !dragged,
              hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) > 4 else { return }
        dragged = true
        let item = NSDraggingItem(pasteboardWriter: shot.url as NSURL)
        item.setDraggingFrame(bounds, contents: shot.image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
