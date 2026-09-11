import SwiftUI
import Observation

@MainActor
@Observable
final class AppEnvironment {
    /// Single shared instance so Settings and the overlay share the same API key and session.
    static let shared = AppEnvironment()

    let settingsStore: SettingsStore
    let permissions: PermissionService
    let session: InterviewSessionManager
    let overlayManager: OverlayManager
    let hotkeys: HotkeyService
    let launchAtLogin: LaunchAtLoginServing
    let screenCapture: ScreenCaptureService
    /// STT (Whisper) always goes through OpenAI directly, regardless of the selected answer provider.
    let openAI: OpenAIClient
    let aiClient: AIClientRouter
    @ObservationIgnored private let regionSelection = RegionSelectionController()
    @ObservationIgnored private var regionCaptureTask: Task<Void, Never>?

    /// Needs `self`, so it can only be built after init finishes.
    @ObservationIgnored
    private lazy var statusItemController = StatusItemController(environment: self)

    private var didBootstrap = false

    private init() {
        let settingsStore = SettingsStore()
        let permissions = PermissionService()
        let screenCapture = ScreenCaptureService()
        let openAI = OpenAIClient()
        let aiClient = AIClientRouter(openAI: openAI)
        let speech = SpeechRecognitionService(transcriber: openAI)
        let ocr = OCRService()
        let contextStore = ContextStore()

        let session = InterviewSessionManager(
            settingsStore: settingsStore,
            permissions: permissions,
            screenCapture: screenCapture,
            ocr: ocr,
            speech: speech,
            aiClient: aiClient,
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
        self.aiClient = aiClient
    }

    func bootstrap() {
        guard !didBootstrap else {
            settingsStore.reloadAPIKeysFromKeychain()
            overlayManager.applyScreenShareExclusionToAllWindows()
            return
        }
        didBootstrap = true

        settingsStore.reloadAPIKeysFromKeychain()
        settingsStore.migratePromptTemplateIfNeeded()
        overlayManager.applyScreenShareExclusionToAllWindows()
        // The overlay is the only window presented at startup.
        overlayManager.present(session: session)

        applyMenuBarIconSetting()

        let captureShortcutRegistered = hotkeys.registerDefaults(
            onToggleOverlay: { [weak self] in
                guard let self else { return }
                self.overlayManager.toggle(session: self.session)
            },
            onTogglePause: { [weak self] in
                guard let self else { return }
                self.session.togglePause()
                if self.session.status == .paused { self.cancelRegionSelection() }
            },
            onCaptureRegion: { [weak self] in
                self?.captureSelectedRegion()
            }
        )
        if !captureShortcutRegistered {
            session.reportRegionCaptureIssue("Could not register ⌃⌥S. Another app may be using it. Use Capture Region in the menu bar, or free the shortcut and restart Smarty.")
        }

        let enabled = launchAtLogin.isEnabled()
        if settingsStore.settings.launchAtLogin != enabled {
            settingsStore.update { $0.launchAtLogin = enabled }
        }
    }

    /// Installs or removes the menu bar item to match Settings → General.
    func applyMenuBarIconSetting() {
        if settingsStore.settings.showMenuBarIcon {
            statusItemController.install()
        } else {
            statusItemController.remove()
        }
    }

    func shutdown() async {
        cancelRegionSelection()
        hotkeys.unregisterAll()
        statusItemController.remove()
        await session.stopSession()
        overlayManager.hide()
    }

    /// Synchronous so temporary input surfaces are removed even as the app terminates.
    func cancelRegionSelection() {
        regionSelection.cancel()
        regionCaptureTask?.cancel()
        // The task clears itself when it exits; do not let a stale completion clear a newer task.
        session.cancelRegionCapture()
    }

    func captureSelectedRegion() {
        guard !regionSelection.isSelecting, regionCaptureTask == nil else { return }
        guard let captureID = session.beginRegionCapture() else {
            overlayManager.present(session: session)
            return
        }
        // Keep the answer overlay out of the user's way until selection finishes.
        let overlayWasVisible = overlayManager.isVisible
        overlayManager.hide()
        regionSelection.begin(blindMode: settingsStore.settings.blindModeEnabled) { [weak self] region in
            guard let self else { return }
            guard let region else {
                self.session.cancelRegionCapture()
                if overlayWasVisible { self.overlayManager.present(session: self.session) }
                return
            }
            self.overlayManager.present(session: self.session)
            self.regionCaptureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.regionCaptureTask = nil }
                await self.session.solveSelectedRegion(region, captureID: captureID)
            }
        }
    }
}
