import AppKit

/// Owns all temporary input surfaces; no global mouse hooks or Accessibility access needed.
@MainActor
final class RegionSelectionController {
    private var panels: [RegionSelectionPanel] = []
    private var completion: ((ScreenRegion?) -> Void)?
    private var displayObserver: NSObjectProtocol?
    private weak var previousKeyWindow: NSWindow?
    private var cursorPushed = false

    var isSelecting: Bool { completion != nil }

    func begin(blindMode: Bool, completion: @escaping (ScreenRegion?) -> Void) {
        guard !isSelecting else { return }
        self.completion = completion
        previousKeyWindow = NSApp.keyWindow
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let panel = RegionSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.sharingType = blindMode ? .none : .readWrite
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.isMovable = false
            panel.ignoresMouseEvents = false
            panel.animationBehavior = .none
            panel.acceptsMouseMovedEvents = true
            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.displayFrame = screen.frame
            view.onFinish = { [weak self] rect in
                self?.finish(rect.map { ScreenRegion(displayID: number.uint32Value, rect: $0) })
            }
            panel.onCancel = { [weak self] in self?.cancel() }
            panel.contentView = view
            panel.initialFirstResponder = view
            panels.append(panel)
        }
        guard !panels.isEmpty else { finish(nil); return }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        NSCursor.crosshair.push()
        cursorPushed = true
        for panel in panels { panel.orderFrontRegardless() }
        let preferred = panels.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? panels[0]
        preferred.makeKey()
    }

    func cancel() { finish(nil) }

    private func finish(_ region: ScreenRegion?) {
        guard let completion else { return }
        self.completion = nil
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        if let previousKeyWindow, previousKeyWindow.isVisible { previousKeyWindow.makeKey() }
        previousKeyWindow = nil
        // All panels are gone before capture begins.
        completion(region)
    }
}

/// Marker type also prevents standard-window chrome restoration on these surfaces.
final class RegionSelectionPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        // Consume other keys while selecting; do not send them to the underlying app.
    }
}

private final class RegionSelectionView: NSView {
    var displayFrame: CGRect = .zero
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selectedRect: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = window?.convertPoint(toScreen: event.locationInWindow)
        selectedRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { updateSelection(event) }

    override func mouseUp(with event: NSEvent) {
        updateSelection(event)
        onFinish?(selectedRect)
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }

    private func updateSelection(_ event: NSEvent) {
        guard let start, let end = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        selectedRect = ScreenRegionGeometry.selection(from: start, to: end, displayFrame: displayFrame)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // A near-transparent surface receives clicks without dimming the whole display.
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()
        guard let rect = selectedRect else { return }
        let local = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        local.fill()
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: local.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        outline.stroke()
    }
}
