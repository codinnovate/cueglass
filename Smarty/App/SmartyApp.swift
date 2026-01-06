import SwiftUI
import AppKit

@main
struct SmartyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var appEnvironment: AppEnvironment { .shared }

    var body: some Scene {
        WindowGroup("Smarty") {
            ContentView()
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
                .background(Color.black)
                .onAppear {
                    appDelegate.environment = appEnvironment
                    appEnvironment.bootstrap()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appEnvironment.settingsStore.reloadAPIKeyFromKeychain()
                }
        }
        .defaultSize(width: 480, height: 420)
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
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

        Settings {
            SettingsView()
                .environment(AppEnvironment.shared)
                .frame(minWidth: 560, minHeight: 520)
                .onAppear {
                    AppEnvironment.shared.settingsStore.reloadAPIKeyFromKeychain()
                }
        }
    }
}
