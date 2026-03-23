import AppKit
import SwiftUI

/// Floating panel that can become key so SwiftUI `TextField` can accept typing,
/// while staying non-activating for normal overlay use.
@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel?
    private var hostingView: NSHostingView<AnyView>?
    private let onFrameChange: (CGRect) -> Void

    private(set) var isVisible: Bool = false

    init(onFrameChange: @escaping (CGRect) -> Void) {
        self.onFrameChange = onFrameChange
        super.init()
    }

    func show<Content: View>(
        rootView: Content,
        frame: CGRect?,
        opacity: Double,
        locked: Bool,
        clickThrough: Bool
    ) {
        let content = AnyView(rootView)
        if panel == nil {
            createPanel(initialFrame: frame)
        }
        guard let panel else { return }

        if let hostingView {
            hostingView.rootView = content
        } else {
            let hosting = NSHostingView(rootView: content)
            // Avoid intrinsicContentSize — expanding Key Terms / answers was crashing Auto Layout.
            hosting.sizingOptions = [.minSize]
            hostingView = hosting
            panel.contentView = hosting
        }

        applyAppearance(opacity: opacity, locked: locked, clickThrough: clickThrough)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func updateRootView<Content: View>(_ rootView: Content) {
        hostingView?.rootView = AnyView(rootView)
    }

    func applyAppearance(opacity: Double, locked: Bool, clickThrough: Bool) {
        guard let panel else { return }
        panel.alphaValue = 1
        _ = opacity
        panel.isMovable = !locked
        // Drag from empty chrome / header; TextField still focuses via KeyablePanel.
        panel.isMovableByWindowBackground = !locked
        panel.ignoresMouseEvents = clickThrough
    }

    /// Call before focusing the ask field so the panel accepts keyboard input.
    func makeKeyForTyping() {
        guard let panel else { return }
        panel.ignoresMouseEvents = false
        if !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            panel?.orderFrontRegardless()
            isVisible = true
        }
    }

    func currentFrame() -> CGRect? {
        panel?.frame
    }

    func owns(_ window: NSWindow) -> Bool {
        window === panel
    }

    /// Overlay-only floating + blind. Never apply this to the main titled window.
    func applyOverlayBlindMode(_ blind: Bool) {
        guard let panel else { return }
        panel.sharingType = blind ? .none : .readWrite
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
    }

    /// Restore standard macOS chrome on the main app window (traffic lights, normal level).
    func restoreStandardWindowChrome(_ window: NSWindow) {
        guard !owns(window) else { return }
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary, .managed]
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private func createPanel(initialFrame: CGRect?) {
        let defaultFrame = CGRect(x: 80, y: 120, width: 420, height: 252)
        let frame = Self.frameOnVisibleScreen(initialFrame ?? defaultFrame)

        let panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.minSize = NSSize(width: 340, height: 210)
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true

        applyOverlayBlindMode(true)

        self.panel = panel
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        persistFrame()
    }

    private func persistFrame() {
        guard let frame = panel?.frame else { return }
        onFrameChange(frame)
    }

    /// Keeps saved frames usable after displays change; otherwise centers on the screen under the mouse.
    private static func frameOnVisibleScreen(_ proposed: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return proposed }

        let mouse = NSEvent.mouseLocation
        let preferred = screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? screens[0]

        if preferred.visibleFrame.intersects(proposed) {
            return proposed
        }

        let visible = preferred.visibleFrame
        let width = min(max(proposed.width, 340), visible.width)
        // Prefer a shorter overlay; keep a usable minimum.
        let height = min(max(proposed.height, 300), min(visible.height, 400))
        let x = visible.midX - width / 2
        let y = visible.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// `NSPanel` defaults `canBecomeKey` to false with `.nonactivatingPanel`, which blocks TextField focus.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Drag handle that moves the hosting window (works even when SwiftUI blocks background drag).
struct WindowDragRegion: NSViewRepresentable {
    var isEnabled: Bool = true

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.isEnabled = isEnabled
    }
}

final class WindowDragNSView: NSView {
    var isEnabled: Bool = true

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        window.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }
}
