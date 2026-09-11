import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment { .shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement + accessory policy: stay out of the Dock / app switcher.
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        environment.bootstrap()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        environment.settingsStore.reloadAPIKeyFromKeychain()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.cancelRegionSelection()
        let environment = self.environment
        Task { @MainActor in
            await environment.shutdown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopening brings back the existing overlay, even when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        environment.overlayManager.present(session: environment.session)
        // Handled here: do not ask AppKit to reopen any other windows.
        return false
    }
}
