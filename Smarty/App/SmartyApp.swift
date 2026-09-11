import SwiftUI
import AppKit

@main
struct SmartyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var appEnvironment: AppEnvironment { .shared }

    var body: some Scene {
        // AppDelegate launches the AppKit overlay; Settings opens only on request.
        Settings {
            SettingsView()
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
                .frame(minWidth: 560, minHeight: 520)
                .onAppear {
                    appEnvironment.settingsStore.reloadAPIKeyFromKeychain()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Session") {
                Button("Start Session") {
                    Task { await appEnvironment.session.startSession() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Stop Session") {
                    Task { await appEnvironment.session.stopSession() }
                }

                Divider()

                Button("Toggle Overlay") {
                    appEnvironment.overlayManager.toggle(session: appEnvironment.session)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Pause / Resume") {
                    appEnvironment.session.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}
