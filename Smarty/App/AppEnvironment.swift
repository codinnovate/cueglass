import SwiftUI
import Observation

@MainActor
@Observable
final class AppEnvironment {
    /// Single shared instance so Settings and the main/overlay windows always share the same API key + session.
    static let shared = AppEnvironment()

    let settingsStore: SettingsStore
    let permissions: PermissionService
    let session: InterviewSessionManager
    let overlayManager: OverlayManager
    let hotkeys: HotkeyService
    let launchAtLogin: LaunchAtLoginServing
    let screenCapture: ScreenCaptureService
    let openAI: OpenAIClient

    private var didBootstrap = false

    private init() {
        let settingsStore = SettingsStore()
        let permissions = PermissionService()
        let screenCapture = ScreenCaptureService()
        let openAI = OpenAIClient()
        let speech = SpeechRecognitionService(transcriber: openAI)
        let ocr = OCRService()
        let contextStore = ContextStore()

        let session = InterviewSessionManager(
            settingsStore: settingsStore,
            permissions: permissions,
            screenCapture: screenCapture,
            ocr: ocr,
            speech: speech,
            openAI: openAI,
            contextStore: contextStore
        )

        self.settingsStore = settingsStore
        self.permissions = permissions
        self.session = session
        self.overlayManager = OverlayManager(settingsStore: settingsStore)
        self.hotkeys = HotkeyService()
        self.launchAtLogin = LaunchAtLoginService()
        self.screenCapture = screenCapture
        self.openAI = openAI
    }

    func bootstrap() {
        guard !didBootstrap else {
            settingsStore.reloadAPIKeyFromKeychain()
            overlayManager.applyScreenShareExclusionToAllWindows()
            return
        }
        didBootstrap = true

        settingsStore.reloadAPIKeyFromKeychain()
        settingsStore.migratePromptTemplateIfNeeded()
        overlayManager.applyScreenShareExclusionToAllWindows()
        // Prefer overlay for interviews; main window uses the same UI and stays open too.
        overlayManager.present(session: session)

        hotkeys.registerDefaults(
            onToggleOverlay: { [weak self] in
                guard let self else { return }
                self.overlayManager.toggle(session: self.session)
            },
            onTogglePause: { [weak self] in
                self?.session.togglePause()
            }
        )

        let enabled = launchAtLogin.isEnabled()
        if settingsStore.settings.launchAtLogin != enabled {
            settingsStore.update { $0.launchAtLogin = enabled }
        }
    }

    func shutdown() async {
        hotkeys.unregisterAll()
        await session.stopSession()
        overlayManager.hide()
    }
}
