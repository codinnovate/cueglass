import AppKit

/// Menu bar entry point for the app.
///
/// `LSUIElement` keeps Cueglass out of the Dock and app switcher. This item and ⌘⇧H can
/// restore a hidden overlay. The item can be hidden in Settings for a clean menu bar.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    var isInstalled: Bool { statusItem != nil }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Wordmark.image()
        item.button?.toolTip = "Cueglass"

        let menu = NSMenu()
        menu.delegate = self
        // Titles are built by hand in menuNeedsUpdate; let them own their enabled state.
        menu.autoenablesItems = false
        item.menu = menu

        statusItem = item
    }

    func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - Menu

    /// Rebuilt on every open so titles track live session state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let session = environment.session
        let overlayVisible = environment.overlayManager.isVisible

        // ⌘⇧H / ⌘⇧P are Carbon hotkeys registered globally by HotkeyService. They are shown
        // as title hints rather than key equivalents so the menu can't double-dispatch them.
        menu.addItem(makeItem(
            title: overlayVisible ? "Hide Overlay  ⌘⇧H" : "Show Overlay  ⌘⇧H",
            action: #selector(toggleOverlay)
        ))

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Capture Region and Answer  ⌃⌥S", action: #selector(captureRegion)))

        menu.addItem(makeItem(
            title: session.isRunning ? "Stop Session" : "Start Session",
            action: #selector(toggleSession)
        ))
        menu.addItem(makeItem(
            title: session.status == .paused ? "Resume  ⌘⇧P" : "Pause  ⌘⇧P",
            action: #selector(togglePause),
            enabled: session.isRunning
        ))

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Settings…", action: #selector(openSettings)))
        menu.addItem(makeItem(title: "Status: \(session.status.label)", action: nil, enabled: false))

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Quit Cueglass", action: #selector(quit), keyEquivalent: "q"))
    }

    private func makeItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled && action != nil
        return item
    }

    // MARK: - Actions

    @objc private func toggleOverlay() {
        environment.overlayManager.toggle(session: environment.session)
    }

    @objc private func captureRegion() {
        // Let menu tracking finish before presenting the selection panels.
        DispatchQueue.main.async { [weak self] in self?.environment.captureSelectedRegion() }
    }

    @objc private func toggleSession() {
        let session = environment.session
        Task { @MainActor in
            if session.isRunning {
                await session.stopSession()
            } else {
                await session.startSession()
            }
        }
    }

    @objc private func togglePause() {
        environment.session.togglePause()
    }

    @objc private func openSettings() {
        // Invoke SwiftUI's native Settings command. Legacy showSettingsWindow: selectors
        // do not open the Settings scene on current macOS versions.
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let index = appMenu.items.firstIndex(where: {
                  $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
              }) else {
            AppLog.overlay.error("Settings command is unavailable")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        appMenu.performActionForItem(at: index)
        // A freshly created settings window starts shareable; re-apply blind mode to it.
        DispatchQueue.main.async { [weak self] in
            self?.environment.overlayManager.applyScreenShareExclusionToAllWindows()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// The `<Cue/>` wordmark, drawn as a template image.
///
/// Drawn rather than shipped as an asset so it stays crisp at any menu bar scale, and template
/// mode lets AppKit handle light/dark tinting and the inversion while the menu is open — a
/// plain button title would stay dark on the highlighted background.
private enum Wordmark {
    static let text = "<Cue/>"

    /// 11.5 semibold keeps the mark ~43pt wide — heavy enough to read as a logo,
    /// narrow enough not to crowd the menu bar.
    static func image(pointSize: CGFloat = 11.5) -> NSImage {
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: pointSize, weight: .semibold),
                // Template mode only reads coverage, so the color here is just a stencil.
                .foregroundColor: NSColor.black
            ]
        )

        let measured = string.size()
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))

        let image = NSImage(size: size)
        image.lockFocus()
        string.draw(at: .zero)
        image.unlockFocus()

        image.isTemplate = true
        image.accessibilityDescription = "Cueglass"
        return image
    }
}
