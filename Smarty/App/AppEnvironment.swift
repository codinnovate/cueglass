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
    /// Always-on-top diagnostics HUD (⌃⌥D or the menu bar item).
    @ObservationIgnored let diagnostics: DiagnosticsPanelController
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
        let gemini = GeminiClient()
        let aiClient = AIClientRouter(openAI: openAI, gemini: gemini)
        let speech = SpeechRecognitionService(openAI: openAI, gemini: gemini)
        let ocr = OCRService()

        let session = InterviewSessionManager(
            settingsStore: settingsStore,
            permissions: permissions,
            screenCapture: screenCapture,
            ocr: ocr,
            speech: speech,
            aiClient: aiClient
        )

        self.settingsStore = settingsStore
        self.permissions = permissions
        self.session = session
        let overlayManager = OverlayManager(settingsStore: settingsStore)
        self.overlayManager = overlayManager
        self.diagnostics = DiagnosticsPanelController(
            session: session,
            settingsStore: settingsStore,
            monitor: DiagnosticsMonitor(
                permissionService: permissions,
                overlayVisible: { [weak overlayManager] in overlayManager?.isVisible ?? false }
            )
        )
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
        diagnostics.restoreIfNeeded()

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
            onSolveScreen: { [weak self] in
                guard let self else { return }
                self.overlayManager.present(session: self.session)
                Task { await self.session.screenshotSolve() }
            },
            onCaptureRegion: { [weak self] in
                self?.captureSelectedRegion()
            },
            onCopyRegionText: { [weak self] in
                self?.copyRegionText()
            },
            onCopyRegionImage: { [weak self] in
                self?.copyRegionImage()
            },
            onToggleDiagnostics: { [weak self] in
                self?.diagnostics.toggle()
            }
        )
        if !captureShortcutRegistered {
            session.reportRegionCaptureIssue("Could not register ⌃⌥S/⌃⌥A/⌃⌥C/⌃⌥R. Another app may be using one of them. Use the menu bar items instead, or free the shortcut and restart Smarty.")
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
        diagnostics.tearDown()
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
        selectRegion(for: .answer)
    }

    /// Region-select → OpenAI vision transcription → clipboard + answer.
    func copyRegionText() {
        selectRegion(for: .copyText)
    }

    /// Region-select → clipboard image + OpenAI vision answer.
    func copyRegionImage() {
        selectRegion(for: .copyImageAndAnswer)
    }

    private enum RegionAction {
        case answer
        case copyText
        case copyImageAndAnswer

        var showsAnswer: Bool {
            switch self {
            case .answer, .copyText, .copyImageAndAnswer: return true
            }
        }
    }

    private func selectRegion(for action: RegionAction) {
        guard !regionSelection.isSelecting, regionCaptureTask == nil else { return }
        let captureID: UUID?
        switch action {
        case .answer: captureID = session.beginRegionCapture()
        case .copyText: captureID = session.beginCopyRegionCapture()
        case .copyImageAndAnswer: captureID = session.beginCopyRegionImageCapture()
        }
        guard let captureID else {
            if action.showsAnswer { overlayManager.present(session: session) }
            return
        }
        let overlayWasVisible = overlayManager.isVisible
        overlayManager.hide()
        regionSelection.begin(blindMode: settingsStore.settings.blindModeEnabled) { [weak self] region in
            guard let self else { return }
            guard let region else {
                self.session.cancelRegionCapture()
                if overlayWasVisible { self.overlayManager.present(session: self.session) }
                return
            }
            if action.showsAnswer || overlayWasVisible {
                self.overlayManager.present(session: self.session)
            }
            self.regionCaptureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.regionCaptureTask = nil }
                switch action {
                case .answer:
                    await self.session.solveSelectedRegion(region, captureID: captureID)
                case .copyText:
                    await self.session.copyRegionTextToClipboard(region, captureID: captureID)
                case .copyImageAndAnswer:
                    await self.session.copyRegionImageToClipboard(region, captureID: captureID)
                }
            }
        }
    }
}
