import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import Speech

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case speechRecognition
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        case .screenRecording: return "Screen Recording"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}

enum PermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    /// Toggle may be ON in Settings, but this process still lacks access until quit + relaunch.
    case needsRelaunch
}

@MainActor
protocol PermissionChecking: AnyObject {
    func requestMicrophone() async -> Bool
    func requestSpeechRecognition() async -> Bool
    func requestScreenRecording() async -> Bool
    func requestAll() async -> (mic: Bool, speech: Bool, screen: Bool)
    func openSystemSettings(for kind: PermissionKind)
    func screenCapturePreflight() -> Bool
}

@MainActor
final class PermissionService: PermissionChecking {
    /// After CGRequest shows the system sheet, this process usually stays denied until relaunch.
    private var didPromptScreenCaptureThisLaunch = false

    func state(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() { return .granted }
            return didPromptScreenCaptureThisLaunch ? .needsRelaunch : .notDetermined
        }
    }

    func screenCapturePreflight() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestMicrophone() async -> Bool {
        await Self.requestMicrophoneAccess()
    }

    func requestSpeechRecognition() async -> Bool {
        await Self.requestSpeechAccess()
    }

    /// Prefer CG preflight/request. Do **not** fall back to SCShareableContent when denied —
    /// that path logs “user declined TCC” even when Settings already shows Smarty enabled,
    /// because the *current process* still lacks the grant until quit + relaunch.
    func requestScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        if !didPromptScreenCaptureThisLaunch {
            didPromptScreenCaptureThisLaunch = true
            _ = CGRequestScreenCaptureAccess()
            if CGPreflightScreenCaptureAccess() {
                return true
            }
            // Open Settings so the user can flip the toggle for this Development-signed build.
            openSystemSettings(for: .screenRecording)
        }

        return CGPreflightScreenCaptureAccess()
    }

    func openSystemSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func requestAll() async -> (mic: Bool, speech: Bool, screen: Bool) {
        let mic = await requestMicrophone()
        let speech = await requestSpeechRecognition()
        let screen = await requestScreenRecording()
        return (mic, speech, screen)
    }

    private nonisolated static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
