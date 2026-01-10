import SwiftUI

/// Main window — same Whisper/Stream UI as the floating overlay.
struct ContentView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var showPermissions = false

    private var session: InterviewSessionManager { appEnvironment.session }
    private var settings: AppSettings { appEnvironment.settingsStore.settings }

    var body: some View {
        VStack(spacing: 0) {
            OverlayView(
                session: session,
                fontSize: settings.overlayFontSize,
                opacity: settings.overlayOpacity,
                assistantMode: settings.assistantMode,
                blindModeEnabled: settings.blindModeEnabled,
                statusBlinkEnabled: settings.statusBlinkEnabled,
                showsCloseButton: false,
                onAppearanceChange: {
                    appEnvironment.overlayManager.refresh(session: session)
                },
                onToggleBlind: {
                    appEnvironment.overlayManager.setBlindMode(
                        !settings.blindModeEnabled,
                        session: session
                    )
                },
                onModeChange: { mode in
                    Task {
                        await session.setAssistantMode(mode)
                        appEnvironment.overlayManager.refresh(session: session)
                    }
                }
            )

            HStack(spacing: 12) {
                Button("Permissions") { showPermissions = true }
                Button("Show Overlay") {
                    appEnvironment.overlayManager.present(session: session)
                }
                Text("⌘⇧H toggles overlay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 420, minHeight: 400)
        .background(.clear)
        .sheet(isPresented: $showPermissions) {
            PermissionGuideView()
                .environment(appEnvironment)
                .frame(width: 460, height: 420)
        }
        .onAppear {
            appEnvironment.overlayManager.applyScreenShareExclusionToAllWindows()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment.shared)
        .frame(width: 440, height: 640)
}
