import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement + accessory policy: stay out of the Dock / app switcher.
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Ensure blind mode + restore main-window traffic lights (close / minimize / zoom).
        // Also pull any restored windows back onto a visible display (external monitor unplugged).
        DispatchQueue.main.async { [weak self] in
            self?.environment?.overlayManager.applyScreenShareExclusionToAllWindows()
            Self.bringWindowsOntoVisibleScreens()
            Self.ensureMainWindowChrome()
        }
    }

    private static func ensureMainWindowChrome() {
        for window in NSApp.windows {
            guard !(window is NSPanel) else { continue }
            window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.level = .normal
            window.isOpaque = true
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private static func bringWindowsOntoVisibleScreens() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Prefer the screen under the mouse (usually where the user is looking).
        let mouse = NSEvent.mouseLocation
        let preferred = screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? screens[0]
        let visible = preferred.visibleFrame

        for window in NSApp.windows where window.isVisible || window.isMiniaturized {
            let frame = window.frame
            let onPreferred = visible.intersects(frame)
            guard !onPreferred else { continue }

            let width = min(max(frame.width, 300), visible.width)
            let height = min(max(frame.height, 300), visible.height)
            let origin = NSPoint(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2
            )
            window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
            window.makeKeyAndOrderFront(nil as AnyObject?)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let environment = self.environment
        Task { @MainActor in
            await environment?.shutdown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
