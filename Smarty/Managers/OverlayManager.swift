import AppKit
import SwiftUI

@MainActor
@Observable
final class OverlayManager {
    private let panelController: OverlayPanelController
    private let settingsStore: SettingsStore

    var isVisible: Bool { panelController.isVisible }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.panelController = OverlayPanelController { [weak settingsStore] frame in
            settingsStore?.update { $0.overlayFrame = CodableRect(frame) }
        }
    }

    func present(session: InterviewSessionManager) {
        let settings = settingsStore.settings
        panelController.show(
            rootView: makeOverlayView(session: session, settings: settings),
            frame: settings.overlayFrame?.cgRect,
            opacity: settings.overlayOpacity,
            locked: settings.positionLocked,
            clickThrough: settings.clickThroughEnabled
        )
        session.isClickThrough = settings.clickThroughEnabled
        session.isPositionLocked = settings.positionLocked
        applyScreenShareExclusionToAllWindows()
    }

    func refresh(session: InterviewSessionManager) {
        let settings = settingsStore.settings
        panelController.updateRootView(makeOverlayView(session: session, settings: settings))
        panelController.applyAppearance(
            opacity: settings.overlayOpacity,
            locked: settings.positionLocked,
            clickThrough: settings.clickThroughEnabled
        )
        session.isClickThrough = settings.clickThroughEnabled
        session.isPositionLocked = settings.positionLocked
    }

    func hide() {
        panelController.hide()
    }

    /// Lets the overlay ask field take keyboard focus (non-activating panels need this).
    func focusOverlayForTyping(session: InterviewSessionManager) {
        if session.isClickThrough {
            setClickThrough(false, session: session)
        }
        panelController.makeKeyForTyping()
    }

    private func setClickThrough(_ enabled: Bool, session: InterviewSessionManager) {
        session.setClickThrough(enabled)
        panelController.applyAppearance(
            opacity: settingsStore.settings.overlayOpacity,
            locked: settingsStore.settings.positionLocked,
            clickThrough: enabled
        )
    }

    private func makeOverlayView(session: InterviewSessionManager, settings: AppSettings) -> OverlayView {
        OverlayView(
            session: session,
            fontSize: settings.overlayFontSize,
            opacity: settings.overlayOpacity,
            assistantMode: settings.assistantMode,
            blindModeEnabled: settings.blindModeEnabled,
            statusBlinkEnabled: settings.statusBlinkEnabled,
            showsCloseButton: true,
            onRequestTypingFocus: { [weak self] in
                self?.focusOverlayForTyping(session: session)
            },
            onAppearanceChange: { [weak self] in
                self?.refresh(session: session)
            },
            onToggleBlind: { [weak self] in
                guard let self else { return }
                self.settingsStore.update { $0.blindModeEnabled.toggle() }
                self.applyScreenShareExclusionToAllWindows()
                self.refresh(session: session)
            },
            onModeChange: { [weak self] mode in
                guard let self else { return }
                Task { @MainActor in
                    await session.setAssistantMode(mode)
                    self.refresh(session: session)
                }
            },
            onCloseOverlay: { [weak self] in
                self?.hide()
            }
        )
    }

    func toggle(session: InterviewSessionManager) {
        if isVisible {
            hide()
        } else {
            present(session: session)
        }
    }

    func setBlindMode(_ enabled: Bool, session: InterviewSessionManager) {
        settingsStore.update { $0.blindModeEnabled = enabled }
        applyScreenShareExclusionToAllWindows()
        refresh(session: session)
    }

    func applyScreenShareExclusionToAllWindows() {
        let blind = settingsStore.settings.blindModeEnabled
        // Floating / transient only on the overlay — applying it to the main WindowGroup
        // removed close/minimize traffic lights and made two “modals” feel broken.
        panelController.applyOverlayBlindMode(blind)
        for window in NSApp.windows {
            if panelController.owns(window) { continue }
            window.sharingType = blind ? .none : .readWrite
            panelController.restoreStandardWindowChrome(window)
        }
    }
}
