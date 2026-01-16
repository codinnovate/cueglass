import Foundation
import CoreGraphics
@testable import Smarty

@MainActor
final class FakePermissionService: PermissionChecking {
    var micGranted = true
    var speechGranted = true
    var screenGranted = true

    func requestMicrophone() async -> Bool { micGranted }
    func requestSpeechRecognition() async -> Bool { speechGranted }
    func requestScreenRecording() async -> Bool { screenGranted }
    func requestAll() async -> (mic: Bool, speech: Bool, screen: Bool) {
        (micGranted, speechGranted, screenGranted)
    }
    func openSystemSettings(for kind: PermissionKind) {}
    func screenCapturePreflight() -> Bool { screenGranted }
}

final class FakeSpeechService: SpeechRecognizing, @unchecked Sendable {
    // Tests drive this from the MainActor; no contended access.
    private nonisolated(unsafe) var _isEngineRunning = false
    private nonisolated(unsafe) var _isMuted = false
    private nonisolated(unsafe) var _hasManualAudio = false
    private nonisolated(unsafe) var _manualPaused = false
    private nonisolated(unsafe) var handler: (@Sendable (SpeechEvent) -> Void)?
    private(set) nonisolated(unsafe) var startCount = 0
    private(set) nonisolated(unsafe) var manualStartCount = 0
    private(set) nonisolated(unsafe) var manualFinishCount = 0
    var shouldFailStart = false
    var manualTranscript = "Whisper question about arrays"
    var shouldFailManualFinish = false

    var isEngineRunning: Bool { _isEngineRunning }
    var isMuted: Bool { _isMuted }
    var hasManualCaptureAudio: Bool { _hasManualAudio }

    func availableMicrophones() async -> [MicrophoneInfo] { [] }

    func start(
        microphoneUID: String?,
        pauseSeconds: TimeInterval,
        apiKey: String,
        handler: @escaping @Sendable (SpeechEvent) -> Void
    ) async throws {
        _ = microphoneUID
        _ = pauseSeconds
        _ = apiKey
        if shouldFailStart { throw SpeechError.unavailable }
        startCount += 1
        self.handler = handler
        _isEngineRunning = true
        _isMuted = false
        _hasManualAudio = false
        _manualPaused = false
    }

    func stop() async {
        _isEngineRunning = false
        _isMuted = false
        _hasManualAudio = false
        _manualPaused = false
        handler = nil
    }

    func setMuted(_ muted: Bool) async {
        _isMuted = muted
    }

    func startManualCapture(microphoneUID: String?, apiKey: String) async throws {
        _ = microphoneUID
        _ = apiKey
        if shouldFailStart { throw SpeechError.unavailable }
        manualStartCount += 1
        handler = nil
        _isEngineRunning = true
        _isMuted = false
        _manualPaused = false
        _hasManualAudio = true
    }

    func pauseManualCapture() async {
        _manualPaused = true
    }

    func resumeManualCapture() async {
        _manualPaused = false
    }

    func cancelManualCapture() async {
        _isEngineRunning = false
        _hasManualAudio = false
        _manualPaused = false
    }

    func finishManualCaptureAndTranscribe() async throws -> String {
        manualFinishCount += 1
        if shouldFailManualFinish { throw SpeechError.emptyCapture }
        _isEngineRunning = false
        _hasManualAudio = false
        _manualPaused = false
        return manualTranscript
    }

    func emit(_ event: SpeechEvent) {
        handler?(event)
    }
}

actor FakeScreenCapture: ScreenCapturing {
    var frame: CGImage?
    var shouldFail = false
    private(set) var startCount = 0

    func availableDisplays() async throws -> [DisplayInfo] {
        [DisplayInfo(id: 1, name: "Test", width: 100, height: 100)]
    }

    func start(displayID: UInt32?, interval: TimeInterval, onFrame: @escaping @Sendable (CGImage) async -> Void) async throws {
        startCount += 1
        if shouldFail { throw ScreenCaptureError.noDisplay }
    }

    func stop() async {}
    func updateInterval(_ interval: TimeInterval) async {}

    func captureFrame(displayID: UInt32?) async throws -> CGImage {
        if shouldFail { throw ScreenCaptureError.noDisplay }
        guard let frame else { throw ScreenCaptureError.noDisplay }
        return frame
    }

    func setFrame(_ value: CGImage?) {
        frame = value
    }
}

actor FakeOCR: OCRProcessing {
    var text: String?
    private(set) var resetCount = 0

    func recognizeText(in image: CGImage, accuracy: OCRAccuracy) async throws -> String? {
        text
    }

    func reset() async {
        resetCount += 1
    }

    func setText(_ value: String?) {
        text = value
    }
}

actor FakeOpenAI: OpenAIClienting {
    var deltas: [String] = ["Hello", " world"]
    var completeText = "Hello world"
    var error: Error?
    /// Artificial delay for answer `complete` calls (lets tests queue pauses mid-generation).
    var completeDelayNanoseconds: UInt64 = 0
    private(set) var streamCallCount = 0
    private(set) var answerCompleteCallCount = 0
    private(set) var lastRequest: OpenAIRequest?

    func streamResponse(apiKey: String, request: OpenAIRequest) -> AsyncThrowingStream<String, Error> {
        streamCallCount += 1
        lastRequest = request
        let deltas = self.deltas
        let error = self.error
        return AsyncThrowingStream { continuation in
            Task {
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                for delta in deltas {
                    continuation.yield(delta)
                }
                continuation.finish()
            }
        }
    }

    func complete(apiKey: String, request: OpenAIRequest) async throws -> String {
        lastRequest = request
        if let error { throw error }
        // Key-terms extraction expects JSON; do not count as an answer request.
        if request.instructions.localizedCaseInsensitiveContains("Extract 3") {
            return """
            [{"term":"Example","definition":"A sample term.","relatedQuestions":["What is Example?"]}]
            """
        }
        answerCompleteCallCount += 1
        if completeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: completeDelayNanoseconds)
        }
        return completeText
    }

    func transcribeAudio(apiKey: String, wavData: Data, prompt: String?) async throws -> String {
        _ = apiKey; _ = wavData; _ = prompt
        if let error { throw error }
        return "transcribed text"
    }

    func setDeltas(_ value: [String]) {
        deltas = value
        completeText = value.joined()
    }

    func setCompleteDelayNanoseconds(_ value: UInt64) {
        completeDelayNanoseconds = value
    }

    func callCount() -> Int {
        // Answers always use the non-streaming complete path now.
        answerCompleteCallCount + streamCallCount
    }
}

final class FakeKeychain: KeychainServing, @unchecked Sendable {
    private var value: String?

    func saveAPIKey(_ key: String) throws { value = key }
    func loadAPIKey() throws -> String? { value }
    func deleteAPIKey() throws { value = nil }
}
