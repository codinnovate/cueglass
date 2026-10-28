import AppKit
import SwiftUI

/// How high the diagnostics widget sits in the system window stack.
///
/// Every option stays above the answer overlay, which itself sits at
/// `OverlayWindowTier.overlay` (`.screenSaver`) to clear full-screen apps. The ladder is
/// expressed relative to that base, and the region picker sits above all of them.
enum DiagnosticsWindowLevel: String, CaseIterable, Identifiable, Sendable {
    case aboveOverlay
    case statusBar
    case popUpMenu
    case system

    static let `default`: DiagnosticsWindowLevel = .system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aboveOverlay: return "Above Overlay"
        case .statusBar: return "Above Menu Bar & Dock"
        case .popUpMenu: return "Above Menus"
        case .system: return "System (Topmost)"
        }
    }

    var shortTitle: String {
        switch self {
        case .aboveOverlay: return "OVL"
        case .statusBar: return "BAR"
        case .popUpMenu: return "MENU"
        case .system: return "SYS"
        }
    }

    var windowLevel: NSWindow.Level {
        let base = OverlayWindowTier.diagnosticsBase.rawValue
        switch self {
        case .aboveOverlay: return NSWindow.Level(rawValue: base)
        case .statusBar: return NSWindow.Level(rawValue: base + 1)
        case .popUpMenu: return NSWindow.Level(rawValue: base + 2)
        case .system: return NSWindow.Level(rawValue: base + 3)
        }
    }
}

/// Owns the always-on-top diagnostics widget: a passive, non-activating panel that follows
/// the user across Spaces and over full-screen apps.
@MainActor
final class DiagnosticsPanelController: NSObject, NSWindowDelegate {
    private enum DefaultsKey {
        static let visible = "smarty.diagnostics.visible"
        static let level = "smarty.diagnostics.level"
        static let collapsed = "smarty.diagnostics.collapsed"
    }

    private static let frameAutosaveName = "smarty.diagnostics.frame"
    static let windowIdentifier = NSUserInterfaceItemIdentifier("smarty.diagnostics")

    private let session: InterviewSessionManager
    private let settingsStore: SettingsStore
    private let monitor: DiagnosticsMonitor
    private let defaults: UserDefaults

    private var panel: DiagnosticsPanel?
    private var hostingView: NSHostingView<DiagnosticsView>?

    private(set) var level: DiagnosticsWindowLevel
    private(set) var isCollapsed: Bool
    var isVisible: Bool { panel?.isVisible ?? false }

    init(
        session: InterviewSessionManager,
        settingsStore: SettingsStore,
        monitor: DiagnosticsMonitor,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.monitor = monitor
        self.defaults = defaults
        self.level = defaults.string(forKey: DefaultsKey.level)
            .flatMap(DiagnosticsWindowLevel.init(rawValue:)) ?? .default
        self.isCollapsed = defaults.bool(forKey: DefaultsKey.collapsed)
        super.init()
    }

    /// Brings the widget back if it was open when the app last quit.
    func restoreIfNeeded() {
        if defaults.bool(forKey: DefaultsKey.visible) { show() }
    }

    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        monitor.start()
        hostingView?.rootView = makeView()
        ensureOnScreen(panel)
        panel.orderFrontRegardless()
        defaults.set(true, forKey: DefaultsKey.visible)
    }

    func hide() {
        panel?.orderOut(nil)
        monitor.stop()
        defaults.set(false, forKey: DefaultsKey.visible)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Stops polling without forgetting that the widget was open, for app shutdown.
    func tearDown() {
        panel?.orderOut(nil)
        monitor.stop()
    }

    func setLevel(_ newLevel: DiagnosticsWindowLevel) {
        level = newLevel
        defaults.set(newLevel.rawValue, forKey: DefaultsKey.level)
        panel?.level = newLevel.windowLevel
        hostingView?.rootView = makeView()
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        defaults.set(collapsed, forKey: DefaultsKey.collapsed)
        hostingView?.rootView = makeView()
    }

    func copyReport() {
        let report = DiagnosticsReport.make(
            session: session,
            settings: settingsStore.settings,
            monitor: monitor,
            level: level
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    // MARK: - Panel

    private func createPanel() {
        let panel = DiagnosticsPanel(
            contentRect: CGRect(x: 0, y: 0, width: DiagnosticsView.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.windowIdentifier
        panel.isFloatingPanel = true
        panel.level = level.windowLevel
        // Present on every Space, over full-screen apps, and out of Exposé / ⌘` cycling.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        // The hosting view sizes the panel to the content; resizes keep the top-left fixed.
        let hosting = NSHostingView(rootView: makeView())
        panel.contentView = hosting
        hostingView = hosting

        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            placeAtDefaultPosition(panel)
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        self.panel = panel
    }

    private func makeView() -> DiagnosticsView {
        DiagnosticsView(
            session: session,
            settingsStore: settingsStore,
            monitor: monitor,
            level: level,
            isCollapsed: isCollapsed,
            onSetLevel: { [weak self] in self?.setLevel($0) },
            onToggleCollapsed: { [weak self] in
                guard let self else { return }
                self.setCollapsed(!self.isCollapsed)
            },
            onCopyReport: { [weak self] in self?.copyReport() },
            onClose: { [weak self] in self?.hide() }
        )
    }

    /// Top-right of the screen under the mouse, clear of the menu bar.
    private func placeAtDefaultPosition(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let inset: CGFloat = 16
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset))
    }

    /// A saved frame can point at a display that is no longer attached.
    private func ensureOnScreen(_ panel: NSPanel) {
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !onScreen { placeAtDefaultPosition(panel) }
    }

    func windowWillClose(_ notification: Notification) {
        monitor.stop()
    }
}

/// Borderless panels refuse key status by default; allow it so the context menu and buttons
/// respond on first click, while `becomesKeyOnlyIfNeeded` keeps focus with the user's app.
private final class DiagnosticsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
