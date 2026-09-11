import XCTest
import CoreGraphics
@testable import Smarty

@MainActor
final class InterviewSessionManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settingsStore: SettingsStore!
    private var permissions: FakePermissionService!
    private var speech: FakeSpeechService!
    private var capture: FakeScreenCapture!
    private var ocr: FakeOCR!
    private var openAI: FakeOpenAI!
    private var manager: InterviewSessionManager!

    override func setUp() async throws {
        let suite = "smarty.tests.session.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let keychain = FakeKeychain()
        settingsStore = SettingsStore(defaults: defaults, keychain: keychain)
        _ = settingsStore.saveAPIKey("sk-test", for: .openAI)
        // Existing Listen/pause tests run in Stream mode; Whisper is the app default.
        settingsStore.update { $0.assistantMode = .stream }
        permissions = FakePermissionService()
        speech = FakeSpeechService()
        capture = FakeScreenCapture()
        ocr = FakeOCR()
        openAI = FakeOpenAI()
        manager = InterviewSessionManager(
            settingsStore: settingsStore,
            permissions: permissions,
            screenCapture: capture,
            ocr: ocr,
            speech: speech,
            aiClient: openAI,
            contextStore: ContextStore()
        )
    }

    func testListenWithoutAPIKeyErrors() async {
        _ = settingsStore.saveAPIKey("", for: .openAI)
        await manager.listenOnce()
        guard case .error(let message) = manager.status else {
            return XCTFail("Expected error status")
        }
        XCTAssertTrue(message.lowercased().contains("api key"))
    }

    func testListenPauseCompletesAnswerWithoutStreaming() async {
        await manager.listenOnce()
        XCTAssertTrue(manager.isListenArmed)
        XCTAssertEqual(manager.status, .listening)
        XCTAssertEqual(speech.startCount, 1)

        speech.emit(.init(kind: .partial("What is your greatest strength")))
        speech.emit(.init(kind: .pauseDetected))

        await waitUntil(timeout: 2) {
            !self.manager.currentAnswer.isEmpty
                && (self.manager.status == .listening || self.manager.status == .idle)
        }

        XCTAssertEqual(manager.currentAnswer, "Hello world")
        XCTAssertEqual(manager.answeredTurns.count, 1)
        XCTAssertEqual(manager.answeredTurns[0].index, 1)
        XCTAssertEqual(manager.answeredTurns[0].answer, "Hello world")
        let calls = await openAI.callCount()
        XCTAssertGreaterThanOrEqual(calls, 2) // technical + friendly
        let last = await openAI.lastRequest
        XCTAssertEqual(last?.stream, false)
        XCTAssertFalse(manager.isListenArmed)
        XCTAssertEqual(manager.history.count, 1)
    }

    func testForceRegenerateBypassesThrottle() async {
        await manager.listenOnce()
        speech.emit(.init(kind: .partial("Question one")))
        speech.emit(.init(kind: .pauseDetected))
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }

        await openAI.setDeltas(["Again"])
        await manager.regenerate()
        await waitUntil(timeout: 2) { self.manager.currentAnswer == "Again" }
        let calls = await openAI.callCount()
        XCTAssertGreaterThanOrEqual(calls, 4) // 2 answers × (technical + friendly)
        XCTAssertEqual(manager.answeredTurns.count, 1)
        XCTAssertEqual(manager.answeredTurns[0].answer, "Again")
    }

    func testNewRequestCancelsPriorStreamAndRecovers() async {
        await openAI.setDeltas(["slow"])
        await manager.listenOnce()
        speech.emit(.init(kind: .partial("Q1")))
        speech.emit(.init(kind: .pauseDetected))

        await manager.listenOnce()
        speech.emit(.init(kind: .partial("Q2 different")))
        speech.emit(.init(kind: .pauseDetected))

        await waitUntil(timeout: 2) {
            self.manager.status == .listening || self.manager.status == .idle
        }
        XCTAssertNotEqual(manager.status, .thinking)
        XCTAssertNotEqual(manager.status, .streaming)
    }

    func testScreenshotDoesNotFakeSpeechRunningThenListenWorks() async {
        await ocr.setText("Implement binary search")
        await capture.setFrame(Self.makeCGImage())

        await manager.screenshotSolve()
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }

        XCTAssertFalse(speech.isEngineRunning)
        XCTAssertEqual(speech.startCount, 0)

        await manager.listenOnce()
        XCTAssertEqual(speech.startCount, 1)
        XCTAssertTrue(speech.isEngineRunning)
        XCTAssertTrue(manager.isListenArmed)
    }

    func testScreenshotEmptyOCRErrorsThenRecovers() async {
        await ocr.setText(nil)
        await capture.setFrame(Self.makeCGImage())
        await manager.screenshotSolve()

        guard case .error = manager.status else {
            return XCTFail("Expected OCR empty error")
        }
        await waitUntil(timeout: 3) {
            if case .error = self.manager.status { return false }
            return true
        }
    }

    func testSpeechOnlyDoesNotAutoAnswerUnlessArmed() async {
        await manager.listenOnce()
        XCTAssertTrue(manager.isListenArmed)
        speech.emit(.init(kind: .partial("armed question")))
        speech.emit(.init(kind: .pauseDetected))
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }
        let calls = await openAI.callCount()

        manager.clearContext()
        speech.emit(.init(kind: .partial("should not auto answer")))
        speech.emit(.init(kind: .pauseDetected))
        try? await Task.sleep(nanoseconds: 300_000_000)
        let callsAfter = await openAI.callCount()
        XCTAssertEqual(callsAfter, calls)
    }

    func testClearContextResetsFingerprints() async {
        await manager.listenOnce()
        speech.emit(.init(kind: .partial("Same question")))
        speech.emit(.init(kind: .pauseDetected))
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }

        manager.clearContext()
        XCTAssertTrue(manager.currentAnswer.isEmpty)
        XCTAssertTrue(manager.answeredTurns.isEmpty)
        XCTAssertTrue(manager.history.isEmpty)

        await manager.listenOnce()
        speech.emit(.init(kind: .partial("Same question")))
        speech.emit(.init(kind: .pauseDetected))
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }
        let calls = await openAI.callCount()
        XCTAssertGreaterThanOrEqual(calls, 4)
    }

    func testPauseDuringThinkingQueuesNextQuestion() async {
        await openAI.setCompleteDelayNanoseconds(250_000_000)
        await openAI.setDeltas(["Answer one"])
        await manager.listenOnce()
        speech.emit(.init(kind: .final("Explain reconciliation")))
        speech.emit(.init(kind: .pauseDetected))

        await waitUntil(timeout: 2) {
            self.manager.status == .thinking || !self.manager.currentAnswer.isEmpty
        }

        // Re-arm Listen while generating — ambient pauses alone must not queue.
        await manager.listenOnce()
        speech.emit(.init(kind: .final("What about virtual DOM")))
        speech.emit(.init(kind: .pauseDetected))

        await waitUntil(timeout: 3) {
            self.manager.answeredTurns.count >= 2
                && (self.manager.status == .listening || self.manager.status == .idle)
        }

        let calls = await openAI.callCount()
        XCTAssertGreaterThanOrEqual(calls, 4)
        XCTAssertEqual(manager.answeredTurns.count, 2)
        XCTAssertEqual(manager.answeredTurns[0].index, 1)
        XCTAssertEqual(manager.answeredTurns[1].index, 2)
        XCTAssertTrue(manager.answeredTurns[0].question.localizedCaseInsensitiveContains("reconciliation"))
        XCTAssertTrue(manager.answeredTurns[1].question.localizedCaseInsensitiveContains("virtual"))
    }

    func testStartSessionDoesNotAutoAnswerOnPause() async {
        await manager.startSession()
        XCTAssertEqual(manager.status, .listening)
        speech.emit(.init(kind: .final("Ambient chatter should not answer")))
        speech.emit(.init(kind: .pauseDetected))
        try? await Task.sleep(nanoseconds: 300_000_000)
        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(manager.answeredTurns.isEmpty)
    }

    func testAmbientPauseDuringThinkingDoesNotQueue() async {
        await openAI.setCompleteDelayNanoseconds(300_000_000)
        await openAI.setDeltas(["Only one"])
        await manager.listenOnce()
        speech.emit(.init(kind: .final("First real question")))
        speech.emit(.init(kind: .pauseDetected))

        await waitUntil(timeout: 2) {
            self.manager.status == .thinking || !self.manager.currentAnswer.isEmpty
        }

        // No Listen re-arm — ambient pause must not become Question 2.
        speech.emit(.init(kind: .final("Random follow-up noise")))
        speech.emit(.init(kind: .pauseDetected))

        await waitUntil(timeout: 3) {
            !self.manager.currentAnswer.isEmpty
                && (self.manager.status == .listening || self.manager.status == .idle)
        }

        let calls = await openAI.callCount()
        XCTAssertGreaterThanOrEqual(calls, 2) // technical + friendly for the one real question
        XCTAssertEqual(manager.answeredTurns.count, 1)
    }

    func testAnswersStackInsteadOfReplace() async {
        await manager.listenOnce()
        speech.emit(.init(kind: .final("First question about arrays")))
        speech.emit(.init(kind: .pauseDetected))
        guard await waitUntil(timeout: 2, condition: { self.manager.answeredTurns.count == 1 }) else { return }

        await openAI.setDeltas(["Second answer"])
        await manager.listenOnce()
        speech.emit(.init(kind: .final("Second question about maps")))
        speech.emit(.init(kind: .pauseDetected))
        guard await waitUntil(timeout: 2, condition: { self.manager.answeredTurns.count == 2 }) else { return }

        XCTAssertEqual(manager.answeredTurns[0].answer, "Hello world")
        XCTAssertEqual(manager.answeredTurns[1].answer, "Second answer")
        XCTAssertEqual(manager.currentAnswer, "Second answer")
        XCTAssertEqual(manager.answeredTurns[0].index, 1)
        XCTAssertEqual(manager.answeredTurns[1].index, 2)
    }

    func testMuteBlocksSpeechDrivenAnswers() async {
        await manager.listenOnce()
        await manager.setMicMuted(true)
        XCTAssertTrue(manager.isMicMuted)
        XCTAssertTrue(speech.isMuted)

        speech.emit(.init(kind: .final("Should be ignored")))
        speech.emit(.init(kind: .pauseDetected))
        try? await Task.sleep(nanoseconds: 250_000_000)

        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(manager.isListenArmed)
    }

    func testWhisperSendTranscribesAndAnswersWithoutPauseDetection() async {
        await manager.setAssistantMode(.whisper)
        XCTAssertEqual(manager.assistantMode, .whisper)

        await manager.toggleWhisperRecording()
        XCTAssertTrue(manager.isWhisperRecording)
        XCTAssertEqual(speech.manualStartCount, 1)

        await openAI.setDeltas(["Whisper answer"])
        await manager.sendWhisperRecording()

        await waitUntil(timeout: 2) {
            self.manager.answeredTurns.count == 1
                && !self.manager.isWhisperTranscribing
        }

        XCTAssertEqual(speech.manualFinishCount, 1)
        XCTAssertEqual(manager.answeredTurns[0].answer, "Whisper answer")
        XCTAssertTrue(manager.answeredTurns[0].question.localizedCaseInsensitiveContains("arrays"))
        // Technical + friendly (+ optional key terms) — at least the two answer calls.
        let calls = await openAI.callCount()
        XCTAssertGreaterThanOrEqual(calls, 2)
        XCTAssertFalse(manager.isListenArmed)
    }

    func testSwitchingToWhisperDisarmsListen() async {
        await manager.listenOnce()
        XCTAssertTrue(manager.isListenArmed)
        await manager.setAssistantMode(.whisper)
        XCTAssertFalse(manager.isListenArmed)
        XCTAssertEqual(manager.assistantMode, .whisper)
    }

    func testWhisperModeIgnoresStreamPauseEvents() async {
        await manager.setAssistantMode(.whisper)
        await manager.toggleWhisperRecording()
        speech.emit(.init(kind: .final("Should not answer from VAD")))
        speech.emit(.init(kind: .pauseDetected))
        try? await Task.sleep(nanoseconds: 250_000_000)
        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(manager.answeredTurns.isEmpty)
    }

    func testReadingOnScreenAnswerDoesNotRequestAIAndStaysArmed() async {
        await openAI.setDeltas([
            "I would start with a hash map for two sum. For each number I check if the complement already exists, otherwise I store the value and index for average linear time."
        ])
        await manager.listenOnce()
        speech.emit(.init(kind: .final("Explain two sum")))
        speech.emit(.init(kind: .pauseDetected))
        await waitUntil(timeout: 2) { self.manager.answeredTurns.count == 1 }

        let callsAfterAnswer = await openAI.callCount()
        await manager.listenOnce()
        XCTAssertTrue(manager.isListenArmed)

        // Candidate reads the answer aloud — must not create Question 2.
        let reading = String(manager.answeredTurns[0].answer.prefix(120))
        speech.emit(.init(kind: .final(reading)))
        speech.emit(.init(kind: .pauseDetected))
        try? await Task.sleep(nanoseconds: 300_000_000)

        let callsAfterReading = await openAI.callCount()
        XCTAssertEqual(callsAfterReading, callsAfterAnswer)
        XCTAssertEqual(manager.answeredTurns.count, 1)
        XCTAssertTrue(manager.isListenArmed)
        XCTAssertTrue(manager.liveTranscript.localizedCaseInsensitiveContains("reading answer"))
    }


    private var testRegion: ScreenRegion {
        ScreenRegion(displayID: 42, rect: CGRect(x: 20, y: 30, width: 200, height: 100))
    }

    func testRegionQuestionSendsImageWithoutOCRAndPreservesAttachments() async throws {
        await capture.setFrame(Self.makeCGImage())
        await ocr.setText(nil)
        let pending = ImageAttachment(data: Data([1, 2, 3]), mimeType: .png)
        _ = manager.addImage(pending)
        let id = try XCTUnwrap(manager.beginRegionCapture())
        await manager.solveSelectedRegion(testRegion, captureID: id)
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }

        let requests = await openAI.imageRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.images.count, 1)
        XCTAssertNotNil(requests.first?.images.first?.makeCGImage())
        XCTAssertTrue(requests.first?.input.contains("selected screenshot") == true)
        XCTAssertEqual(manager.pendingImages, [pending])
        XCTAssertEqual(manager.answeredTurns.first?.question, "Selected screenshot question")
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(speech.startCount, 0)
        XCTAssertEqual(permissions.screenRequestCount, 0)
        let captured = await capture.regionRequests
        XCTAssertEqual(captured, [testRegion])
    }

    func testRegionOCRFailureStillSendsImage() async throws {
        await capture.setFrame(Self.makeCGImage())
        await ocr.setShouldFail(true)
        let id = try XCTUnwrap(manager.beginRegionCapture())
        await manager.solveSelectedRegion(testRegion, captureID: id)
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }
        let requests = await openAI.imageRequests
        XCTAssertEqual(requests.count, 1)
    }

    func testRegionOCRIncludedWithImage() async throws {
        await capture.setFrame(Self.makeCGImage())
        await ocr.setText("Find the area of this triangle")
        let id = try XCTUnwrap(manager.beginRegionCapture())
        await manager.solveSelectedRegion(testRegion, captureID: id)
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }
        let requests = await openAI.imageRequests
        XCTAssertTrue(requests.first?.input.contains("Find the area of this triangle") == true)
        XCTAssertEqual(manager.answeredTurns.first?.question, "Find the area of this triangle")
    }

    func testRegionPreflightReportsMissingSetupWithoutPrompting() {
        _ = settingsStore.saveAPIKey("", for: .openAI)
        XCTAssertNil(manager.beginRegionCapture())
        XCTAssertTrue(manager.lastErrorMessage?.contains("API key") == true)
        _ = settingsStore.saveAPIKey("sk-test", for: .openAI)
        permissions.screenGranted = false
        XCTAssertNil(manager.beginRegionCapture())
        XCTAssertTrue(manager.lastErrorMessage?.contains("Screen Recording") == true)
        XCTAssertEqual(permissions.screenRequestCount, 0)
        XCTAssertNil(manager.regionCaptureMessage)
    }

    func testRegionCannotBeginWhilePausedOrGenerating() async {
        await manager.listenOnce()
        manager.pause()
        XCTAssertNil(manager.beginRegionCapture())
        XCTAssertEqual(manager.status, .paused)
        manager.resume()
        await openAI.setCompleteDelayNanoseconds(200_000_000)
        await manager.askTyped("Existing question")
        XCTAssertEqual(manager.status, .thinking)
        XCTAssertNil(manager.beginRegionCapture())
        XCTAssertEqual(manager.status, .thinking)
        await waitUntil(timeout: 2) { !self.manager.currentAnswer.isEmpty }
    }

    func testRepeatedCaptureAndCancelledTokenCannotSubmit() async throws {
        let id = try XCTUnwrap(manager.beginRegionCapture())
        XCTAssertNil(manager.beginRegionCapture())
        manager.cancelRegionCapture()
        await manager.solveSelectedRegion(testRegion, captureID: id)
        let captured = await capture.regionRequests
        XCTAssertTrue(captured.isEmpty)
        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(manager.regionCaptureMessage)
        XCTAssertNotNil(manager.beginRegionCapture())
        manager.cancelRegionCapture()
    }

    func testCancellationDuringCaptureDoesNotAnswerOrClearNewSelection() async throws {
        await capture.setFrame(Self.makeCGImage())
        await capture.setRegionDelay(100_000_000)
        let id = try XCTUnwrap(manager.beginRegionCapture())
        let task = Task { await manager.solveSelectedRegion(testRegion, captureID: id) }
        await waitForRegionCaptureStart()
        manager.cancelRegionCapture()
        let newID = try XCTUnwrap(manager.beginRegionCapture())
        await task.value
        XCTAssertNotNil(manager.regionCaptureMessage)
        XCTAssertNotEqual(id, newID)
        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        manager.cancelRegionCapture()
    }

    func testCaptureFailureClearsReservationAndAllowsRetry() async throws {
        let id = try XCTUnwrap(manager.beginRegionCapture())
        await manager.solveSelectedRegion(testRegion, captureID: id)
        XCTAssertNotNil(manager.lastErrorMessage)
        XCTAssertNil(manager.regionCaptureMessage)
        XCTAssertNotNil(manager.beginRegionCapture())
        manager.cancelRegionCapture()
    }

    func testStoppingDuringRegionCapturePreventsAnswer() async throws {
        await capture.setFrame(Self.makeCGImage())
        await capture.setRegionDelay(100_000_000)
        let id = try XCTUnwrap(manager.beginRegionCapture())
        let task = Task { await manager.solveSelectedRegion(testRegion, captureID: id) }
        await waitForRegionCaptureStart()
        await manager.stopSession()
        await task.value
        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(manager.status, .idle)
        XCTAssertNil(manager.regionCaptureMessage)
    }

    func testRegionAPIFailureIsReportedAndRecovers() async throws {
        await capture.setFrame(Self.makeCGImage())
        await openAI.setError(URLError(.notConnectedToInternet))
        let id = try XCTUnwrap(manager.beginRegionCapture())
        await manager.solveSelectedRegion(testRegion, captureID: id)
        await waitUntil(timeout: 2) { self.manager.lastErrorMessage != nil }
        XCTAssertNil(manager.regionCaptureMessage)
        await waitUntil(timeout: 3) { self.manager.status == .idle }
    }

    func testTypedAndAskNowSubmissionsLeavePendingImagesWhileSelecting() async throws {
        await manager.startSession()
        let image = ImageAttachment(data: Data([1, 2, 3]), mimeType: .png)
        _ = manager.addImage(image)
        _ = try XCTUnwrap(manager.beginRegionCapture())
        await manager.askTyped("My draft")
        await manager.askNow()
        XCTAssertEqual(manager.pendingImages, [image])
        let calls = await openAI.callCount()
        XCTAssertEqual(calls, 0)
        manager.cancelRegionCapture()
        await manager.stopSession()
    }

    private func waitForRegionCaptureStart() async {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if !(await capture.regionRequests).isEmpty { return }
            await Task.yield()
        }
        XCTFail("Region capture did not begin")
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
        return false
    }

    private static func makeCGImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
