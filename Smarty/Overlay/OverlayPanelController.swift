import AppKit
import SwiftUI

/// Window levels for the app's floating surfaces.
///
/// `.floating` (level 3) sits below native full-screen content, so a panel at that level
/// disappears when another app is in full screen. macOS requires `.screenSaver` (level 1000)
/// to stay above another app's full-screen Space.
enum OverlayWindowTier {
    /// Answer overlay: visible across Spaces and over full-screen apps.
    static let overlay = NSWindow.Level.screenSaver
    /// Opt-in level for apps that use a window above the screen saver level.
    static let maximum = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 2)
    /// Lowest level of the diagnostics HUD; its options ascend from here, above the overlay.
    static let diagnosticsBase = NSWindow.Level(rawValue: overlay.rawValue + 1)
    /// Region/marquee picker: the topmost surface while a selection is in progress.
    static let regionPicker = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
}

/// Floating panel that can become key so SwiftUI `TextField` can accept typing,
/// while staying non-activating for normal overlay use.
@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("smarty.overlay")
    private var panel: KeyablePanel?
    private var hostingView: NSHostingView<AnyView>?
    private let onFrameChange: (CGRect) -> Void
    private var spaceChangeObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var reassertTask: Task<Void, Never>?

    private(set) var isVisible: Bool = false

    init(onFrameChange: @escaping (CGRect) -> Void) {
        self.onFrameChange = onFrameChange
        super.init()
        // A `canJoinAllSpaces` panel isn't always composited onto a newly activated full-screen
        // Space on its own, so re-assert the overlay once the Space transition settles.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReassertion() }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReassertion() }
        }
    }

    private func scheduleReassertion() {
        reassertTask?.cancel()
        reassertOnActiveSpace()
        reassertTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.reassertOnActiveSpace()
        }
    }

    /// Re-orders the overlay to the front of the now-active Space (including another app's
    /// full-screen Space) so it stays visible after a Space or full-screen transition.
    private func reassertOnActiveSpace() {
        guard isVisible, let panel else { return }
        panel.orderFrontRegardless()
    }

    func show<Content: View>(
        rootView: Content,
        frame: CGRect?,
        opacity: Double,
        locked: Bool,
        clickThrough: Bool,
        blindMode: Bool,
        aboveEverything: Bool
    ) {
        let content = AnyView(rootView)
        if panel == nil {
            createPanel(initialFrame: frame)
        }
        guard let panel else { return }

        applyOverlayBlindMode(blindMode, aboveEverything: aboveEverything)

        if let hostingView {
            hostingView.rootView = content
        } else {
            let hosting = NSHostingView(rootView: content)
            // The panel owns its size. Publishing SwiftUI's minSize here makes AppKit
            // treat the entire vertical stack as a window-size constraint, preventing
            // the user from shortening the overlay even though its answer is scrollable.
            hosting.sizingOptions = []
            hostingView = hosting
            panel.contentView = hosting
        }

        applyAppearance(opacity: opacity, locked: locked, clickThrough: clickThrough)
        // Reopening after a monitor disconnect must also recover an already-created panel.
        let visibleFrame = Self.frameOnVisibleScreen(panel.frame)
        if visibleFrame != panel.frame { panel.setFrame(visibleFrame, display: false) }
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
        reassertTask?.cancel()
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

    /// Overlay-only floating behavior and best-effort sharing exclusion.
    func applyOverlayBlindMode(_ blind: Bool, aboveEverything: Bool) {
        guard let panel else { return }
        panel.sharingType = blind ? .none : .readWrite
        // `canJoinAllApplications` + `fullScreenAuxiliary` let the panel ride other apps'
        // full-screen Spaces; `ignoresCycle` (not `transient`) keeps it out of Exposé / ⌘`.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A captured display may still prevent ordinary windows from appearing.
        panel.level = aboveEverything ? OverlayWindowTier.maximum : OverlayWindowTier.overlay
        panel.backgroundColor = .clear
        panel.isOpaque = false
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
        panel.identifier = Self.windowIdentifier
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.minSize = NSSize(width: 340, height: 120)
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true

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
