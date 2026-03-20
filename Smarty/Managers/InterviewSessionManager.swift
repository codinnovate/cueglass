import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class InterviewSessionManager {
    private(set) var status: AppStatus = .idle
    private(set) var currentAnswer: String = ""
    /// Stacked Q&A blocks — UI renders this list; newer answers append below.
    private(set) var answeredTurns: [AnswerTurn] = []
    private(set) var history: [ConversationMessage] = []
    private(set) var liveTranscript: String = ""
    private(set) var lastErrorMessage: String?

    var isClickThrough: Bool = false
    var isPositionLocked: Bool = false
    /// UI-level session active (speech and/or continuous capture).
    var isRunning: Bool = false
    /// True after Listen is pressed — next pause triggers an answer.
    private(set) var isListenArmed: Bool = false
    /// Mic muted — audio ignored; screen OCR stays passive context only.
    private(set) var isMicMuted: Bool = false
    /// Technical terms extracted from the latest answer (definitions + follow-ups).
    private(set) var keyTerms: [KeyTermCard] = []
    /// Whisper mode: mic is actively capturing (not paused).
    private(set) var isWhisperRecording = false
    /// Whisper mode: capture started but paused (buffer kept).
    private(set) var isWhisperRecordingPaused = false
    /// Whisper mode: STT in flight after Send.
    private(set) var isWhisperTranscribing = false
    /// Images pending attach to the next typed / Ask Now request.
    private(set) var pendingImages: [ImageAttachment] = []
    /// Whisper mode: recording or paused (buffer still held).
    var isWhisperCaptureActive: Bool {
        isWhisperRecording || isWhisperRecordingPaused
    }
    /// Send is available while recording (click Send to stop + answer) or after pause with audio.
    var canSendWhisperRecording: Bool {
        !isWhisperTranscribing
            && (isWhisperRecording || isWhisperRecordingPaused || speech.hasManualCaptureAudio)
    }
    /// Cancel discards the in-progress Whisper take (recording or paused).
    var canCancelWhisperRecording: Bool {
        isWhisperCaptureActive && !isWhisperTranscribing
    }
    /// Elapsed capture time that freezes while paused (WhatsApp-style).
    private var whisperElapsedBase: TimeInterval = 0
    private var whisperSegmentStartedAt: Date?

    private let settingsStore: SettingsStore
    private let permissions: any PermissionChecking
    private let screenCapture: any ScreenCapturing
    private let ocr: any OCRProcessing
    private let speech: any SpeechRecognizing
    private let openAI: any OpenAIClienting
    private let contextStore: ContextStore
    private let summarizer: ContextSummarizer
    private var streamTask: Task<Void, Never>?
    private var summarizeTask: Task<Void, Never>?
    private var keyTermsTask: Task<Void, Never>?
    private var recoverTask: Task<Void, Never>?
    private var lastRequestAt: Date = .distantPast
    private var lastQuestionFingerprint: String = ""
    private var pendingQuestion: String = ""
    private var answerOnNextPause = false
    private var speechOnlyMode = false
    /// When true, stop the mic after the in-flight answer finishes (listen-once).
    private var stopSpeechAfterAnswer = false
    private var allowAIWithoutFullSession = false
    /// Blocks OCR/speech from starting a second answer that cancels the stream mid-way.
    private var isGeneratingAnswer = false
    private var activeGenerationID = UUID()
    /// Question text for the in-flight generation (shown as Question N).
    private var inFlightDisplayQuestion: String = ""
    /// When true, finishAnswer replaces the latest turn instead of appending.
    private var replaceLatestTurnOnFinish = false
    /// Pause heard while answering — answered after the current turn completes.
    private var queuedNextQuestion: String?

    init(
        settingsStore: SettingsStore,
        permissions: any PermissionChecking = PermissionService(),
        screenCapture: any ScreenCapturing = ScreenCaptureService(),
        ocr: any OCRProcessing = OCRService(),
        speech: any SpeechRecognizing = SpeechRecognitionService(),
        openAI: any OpenAIClienting = OpenAIClient(),
        contextStore: ContextStore = ContextStore()
    ) {
        self.settingsStore = settingsStore
        self.permissions = permissions
        self.screenCapture = screenCapture
        self.ocr = ocr
        self.speech = speech
        self.openAI = openAI
        self.contextStore = contextStore
        self.summarizer = ContextSummarizer(openAI: openAI)
        self.history = settingsStore.recentHistory
    }

    static var preview: InterviewSessionManager {
        let manager = InterviewSessionManager(settingsStore: SettingsStore())
        manager.status = .listening
        let answer = """
        I'd clarify constraints, then sketch the approach.

        ```swift
        func twoSum(_ nums: [Int], _ target: Int) -> [Int] {
            var seen: [Int: Int] = [:]
            for (i, n) in nums.enumerated() {
                if let j = seen[target - n] { return [j, i] }
                seen[n] = i
            }
            return []
        }
        ```
        """
        manager.currentAnswer = answer
        manager.answeredTurns = [
            AnswerTurn(
                index: 1,
                question: "Can you implement two sum in Swift?",
                answer: answer
            )
        ]
        manager.liveTranscript = "Can you implement two sum in Swift?"
        return manager
    }

    func startSession() async {
        guard settingsStore.settings.assistantMode == .stream else {
            presentError("Start Session is for Stream mode. Use the mic + Send in Whisper.")
            return
        }
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }

        if isRunning && !speechOnlyMode && speech.isEngineRunning {
            return
        }

        let perms = await permissions.requestAll()
        guard perms.mic else {
            presentError("Microphone permission is required.")
            return
        }
        // Apple Speech permission is optional — listening uses OpenAI STT.
        if !perms.screen {
            lastErrorMessage = Self.screenRecordingHelpMessage
        } else {
            lastErrorMessage = nil
        }

        do {
            try await ensureSpeechRunning(markSpeechOnly: false)
        } catch {
            presentError(error.localizedDescription)
            return
        }

        speechOnlyMode = false
        isRunning = true
        status = .listening

        let settings = settingsStore.settings
        do {
            try await screenCapture.start(
                displayID: settings.selectedDisplayID,
                interval: settings.captureInterval
            ) { [weak self] image in
                await self?.handleFrame(image)
            }
        } catch {
            lastErrorMessage = "Screen capture unavailable: \(error.localizedDescription). Speech-only mode."
            AppLog.capture.error("Capture failed to start: \(error.localizedDescription)")
        }
    }

    func stopSession() async {
        isRunning = false
        speechOnlyMode = false
        stopSpeechAfterAnswer = false
        answerOnNextPause = false
        isListenArmed = false
        isMicMuted = false
        allowAIWithoutFullSession = false
        queuedNextQuestion = nil
        isWhisperRecording = false
        isWhisperRecordingPaused = false
        isWhisperTranscribing = false
        // Invalidate any in-flight generation so awaits after stop cannot resume streaming.
        activeGenerationID = UUID()
        isGeneratingAnswer = false
        streamTask?.cancel()
        streamTask = nil
        summarizeTask?.cancel()
        summarizeTask = nil
        keyTermsTask?.cancel()
        keyTermsTask = nil
        recoverTask?.cancel()
        await speech.stop()
        await screenCapture.stop()
        status = .idle
    }

    var assistantMode: AssistantMode {
        settingsStore.settings.assistantMode
    }

    func setAssistantMode(_ mode: AssistantMode) async {
        guard settingsStore.settings.assistantMode != mode else { return }
        settingsStore.update { $0.assistantMode = mode }
        if mode == .whisper {
            answerOnNextPause = false
            isListenArmed = false
            stopSpeechAfterAnswer = false
            queuedNextQuestion = nil
            await speech.stop()
            if status == .listening { status = .idle }
            liveTranscript = "Whisper mode — tap mic, then Send"
        } else {
            resetWhisperCaptureState()
            await speech.cancelManualCapture()
            liveTranscript = "Stream mode — press Listen for the next pause"
            if isRunning { status = .listening }
        }
    }

    func toggleMicMute() async {
        isMicMuted.toggle()
        await speech.setMuted(isMicMuted)
        if isMicMuted {
            liveTranscript = "Mic muted"
        }
    }

    func setMicMuted(_ muted: Bool) async {
        guard isMicMuted != muted else { return }
        isMicMuted = muted
        await speech.setMuted(muted)
        if muted {
            liveTranscript = "Mic muted"
        }
    }

    func pause() {
        guard isRunning else { return }
        status = .paused
    }

    func resume() {
        guard isRunning else { return }
        status = .listening
    }

    func togglePause() {
        if status == .paused {
            resume()
        } else if isRunning {
            pause()
        }
    }

    func clearContext() {
        Task { await contextStore.clear() }
        history = []
        settingsStore.clearHistory()
        currentAnswer = ""
        answeredTurns = []
        liveTranscript = ""
        keyTerms = []
        lastQuestionFingerprint = ""
        pendingQuestion = ""
        queuedNextQuestion = nil
        answerOnNextPause = false
        isListenArmed = false
        clearImages()
        if isRunning && status != .paused {
            status = .listening
        }
    }

    func copyCurrentAnswer() {
        guard !currentAnswer.isEmpty else { return }
        let payload = answeredTurns.last?.combinedForCopy ?? currentAnswer
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }

    // MARK: - Image attachments

    @discardableResult
    func addImage(_ attachment: ImageAttachment) -> Bool {
        guard pendingImages.count < 6 else { return false }
        pendingImages.append(attachment)
        return true
    }

    func removeImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    func clearImages() {
        pendingImages = []
    }

    @discardableResult
    func pasteFromClipboard() -> Bool {
        guard let attachment = ImageAttachment.fromPasteboard() else { return false }
        return addImage(attachment)
    }

    @discardableResult
    func addImage(fromFileURL url: URL) -> Bool {
        guard let attachment = ImageAttachment.make(fromFileURL: url) else { return false }
        return addImage(attachment)
    }

    /// Markdown export of the current session Q&A stack.
    func exportTranscriptMarkdown() -> String {
        var lines: [String] = [
            "# Cueglass interview transcript",
            "",
            "_Exported \(ISO8601DateFormatter().string(from: Date()))_",
            ""
        ]
        if answeredTurns.isEmpty {
            lines.append("_No answers yet._")
            return lines.joined(separator: "\n")
        }
        for turn in answeredTurns {
            lines.append("## Question \(turn.index)")
            lines.append("")
            lines.append(turn.question.isEmpty ? "_No question text_" : turn.question)
            lines.append("")
            if !turn.technicalAnswer.isEmpty {
                lines.append("### Technical (spoken)")
                lines.append("")
                lines.append(turn.technicalAnswer)
                lines.append("")
            }
            if !turn.friendlyAnswer.isEmpty {
                lines.append("### Simple")
                lines.append("")
                lines.append(turn.friendlyAnswer)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    func copyTranscriptMarkdown() {
        let markdown = exportTranscriptMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func regenerate() async {
        guard status != .paused else { return }
        // Allow retry after listen-once (mic already stopped) when an answer exists.
        guard isRunning || allowAIWithoutFullSession || !currentAnswer.isEmpty else { return }
        allowAIWithoutFullSession = true
        await requestAI(
            force: true,
            skipSummarization: true,
            interruptCurrent: true,
            replaceLatestTurn: true
        )
    }

    func askNow() async {
        guard isRunning, status != .paused else { return }
        let images = takePendingImages()
        await ingestAttachedImageOCR(images)
        await requestAI(
            force: true,
            skipSummarization: true,
            interruptCurrent: true,
            images: images
        )
    }

    /// Typed question from the overlay/main ask field.
    func askTyped(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = takePendingImages()
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }
        guard status != .paused else { return }

        let display = trimmed.isEmpty ? "Attached image question" : trimmed

        if isGeneratingAnswer || status == .thinking || status == .streaming {
            queueNextQuestionIfAppropriate(display, userInitiated: true)
            // Re-queue images if we couldn't send yet.
            for image in images { _ = addImage(image) }
            return
        }

        pendingQuestion = display
        allowAIWithoutFullSession = true
        lastErrorMessage = nil
        await ingestAttachedImageOCR(images)

        let questionBlock = trimmed.isEmpty
            ? "The candidate attached image(s). Solve or answer based on the images and any OCR context."
            : """
            The candidate typed this question. Answer it as if speaking aloud in an interview —
            natural first-person explanation, not a textbook description. Use markdown when helpful
            (short lists, examples, fenced code). Keep everyday grammar light; keep technical terms precise.

            Question:
            \(trimmed)
            """

        await requestAI(
            force: true,
            skipSummarization: true,
            interruptCurrent: true,
            displayQuestion: display,
            userOverride: questionBlock,
            images: images
        )
    }

    /// Ask-field submit: typed text if present, otherwise treat as manual “I’m done speaking” and answer from Heard.
    func submitAskField(_ typed: String) async {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty || !pendingImages.isEmpty {
            await askTyped(trimmed)
            return
        }
        await confirmHeardAndAnswer()
    }

    /// Force-answer from the current live transcript / pending question (manual pause).
    func confirmHeardAndAnswer() async {
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }
        guard status != .paused else { return }

        let heard = [pendingQuestion, liveTranscript]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let heard else {
            presentError("Nothing heard yet — speak a question, or type one below.")
            return
        }

        if isGeneratingAnswer || status == .thinking || status == .streaming {
            queueNextQuestionIfAppropriate(heard, userInitiated: true)
            return
        }

        pendingQuestion = heard
        answerOnNextPause = false
        isListenArmed = false
        allowAIWithoutFullSession = true
        lastErrorMessage = nil
        if speechOnlyMode {
            stopSpeechAfterAnswer = true
        }

        await requestAI(
            force: true,
            skipSummarization: true,
            interruptCurrent: true,
            displayQuestion: heard,
            userOverride: """
            Answer the interviewer's question from this speech transcript as spoken interview words —
            natural first-person explanation I can read aloud. Use markdown for examples/code when useful.
            Everyday grammar can be light; technical terms must stay accurate.

            The transcript may contain ASR mistakes. Infer the intended meaning
            (e.g. "active fiber" / "virtual" → React Fiber vs Virtual DOM).

            Transcript:
            \(heard)
            """
        )
    }

    var canSubmitHeard: Bool {
        let heard = !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Allow submit even while generating so the user can queue the next question.
        return (heard || !pendingImages.isEmpty) && status != .paused
    }

    /// Record from the mic until a pause, then generate an answer. (Stream mode only.)
    func listenOnce() async {
        guard settingsStore.settings.assistantMode == .stream else {
            presentError("Switch to Stream mode to use Listen.")
            return
        }
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }
        // Allow re-arming while an answer is generating — mic keeps capturing; pauses queue.
        if isGeneratingAnswer || status == .thinking || status == .streaming {
            answerOnNextPause = true
            isListenArmed = true
            return
        }

        let micOK = await permissions.requestMicrophone()
        guard micOK else {
            presentError("Microphone permission is required.")
            return
        }
        // OpenAI STT only needs the mic (+ API key). Apple Speech permission is optional.

        do {
            try await ensureSpeechRunning(markSpeechOnly: !isRunning || speechOnlyMode)
        } catch {
            presentError(error.localizedDescription)
            return
        }

        isRunning = true
        liveTranscript = ""
        pendingQuestion = ""
        answerOnNextPause = true
        isListenArmed = true
        status = .listening
        lastErrorMessage = nil
    }

    /// Capture the screen once, OCR the problem, and return a solution — without faking a speech session.
    func screenshotSolve() async {
        await performScreenshotSolve(accuracy: .accurate)
    }

    /// Whisper mode: fast OCR path for snappy screen answers.
    func whisperScreenshotSolve() async {
        await performScreenshotSolve(accuracy: .fast)
    }

    /// Whisper: tap mic to start / pause / resume recording (no pause VAD).
    func toggleWhisperRecording() async {
        guard settingsStore.settings.assistantMode == .whisper else { return }
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }
        guard !isWhisperTranscribing else { return }

        if isWhisperRecording {
            await speech.pauseManualCapture()
            pauseWhisperTimer()
            isWhisperRecording = false
            isWhisperRecordingPaused = true
            liveTranscript = "Paused — Send, resume, or cancel"
            return
        }

        if isWhisperRecordingPaused {
            await speech.resumeManualCapture()
            resumeWhisperTimer()
            isWhisperRecording = true
            isWhisperRecordingPaused = false
            liveTranscript = "Recording… tap Send when done"
            return
        }

        let micOK = await permissions.requestMicrophone()
        guard micOK else {
            presentError("Microphone permission is required.")
            return
        }

        do {
            try await speech.startManualCapture(
                microphoneUID: settingsStore.settings.selectedMicrophoneUID,
                apiKey: settingsStore.apiKey
            )
            startWhisperTimer()
            isWhisperRecording = true
            isWhisperRecordingPaused = false
            lastErrorMessage = nil
            liveTranscript = "Recording… tap Send anytime to answer"
            if status != .thinking { status = .listening }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    /// Whisper: discard the current take without sending (WhatsApp-style cancel).
    func cancelWhisperRecording() async {
        guard settingsStore.settings.assistantMode == .whisper else { return }
        guard canCancelWhisperRecording else { return }

        await speech.cancelManualCapture()
        resetWhisperCaptureState()
        liveTranscript = ""
        if status == .listening { status = .idle }
    }

    /// Elapsed Whisper capture time at `date` (freezes while paused).
    func whisperRecordingElapsed(at date: Date = Date()) -> TimeInterval {
        let live = whisperSegmentStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(0, whisperElapsedBase + live)
    }

    /// Whisper: while recording, Send stops capture automatically → STT → answer.
    func sendWhisperRecording() async {
        guard settingsStore.settings.assistantMode == .whisper else { return }
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }
        guard !isWhisperTranscribing else { return }
        guard isWhisperRecording || isWhisperRecordingPaused || speech.hasManualCaptureAudio else {
            presentError("Start recording first, then tap Send.")
            return
        }

        // Stop/pause UI state immediately — finishManualCapture drains whatever was buffered.
        pauseWhisperTimer()
        isWhisperRecording = false
        isWhisperRecordingPaused = false
        isWhisperTranscribing = true
        liveTranscript = "Transcribing…"
        if status != .thinking { status = .listening }

        do {
            let transcript = try await speech.finishManualCaptureAndTranscribe()
            isWhisperTranscribing = false
            resetWhisperTimer()
            if isCandidateReadingAnswer(transcript) {
                liveTranscript = "You (reading answer) — ignored as a new question"
                status = .idle
                return
            }
            liveTranscript = transcript
            pendingQuestion = transcript
            allowAIWithoutFullSession = true
            await contextStore.appendTranscript(TranscriptChunk(text: transcript, isFinal: true))
            await requestAI(
                force: true,
                skipSummarization: true,
                interruptCurrent: true,
                displayQuestion: transcript,
                userOverride: Self.speechAnswerOverride(for: transcript)
            )
        } catch {
            isWhisperTranscribing = false
            resetWhisperTimer()
            status = .idle
            presentError(error.localizedDescription)
        }
    }

    private func startWhisperTimer() {
        whisperElapsedBase = 0
        whisperSegmentStartedAt = Date()
    }

    private func pauseWhisperTimer() {
        if let started = whisperSegmentStartedAt {
            whisperElapsedBase += Date().timeIntervalSince(started)
            whisperSegmentStartedAt = nil
        }
    }

    private func resumeWhisperTimer() {
        whisperSegmentStartedAt = Date()
    }

    private func resetWhisperTimer() {
        whisperElapsedBase = 0
        whisperSegmentStartedAt = nil
    }

    private func resetWhisperCaptureState() {
        isWhisperRecording = false
        isWhisperRecordingPaused = false
        isWhisperTranscribing = false
        resetWhisperTimer()
    }

    private func performScreenshotSolve(accuracy: OCRAccuracy) async {
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }
        guard status != .thinking, status != .streaming else { return }

        let screenOK = await permissions.requestScreenRecording()
        guard screenOK else {
            presentError(Self.screenRecordingHelpMessage)
            return
        }

        lastErrorMessage = nil
        allowAIWithoutFullSession = true

        do {
            let image = try await screenCapture.captureFrame(
                displayID: settingsStore.settings.selectedDisplayID
            )
            await ocr.reset()
            guard let text = try await ocr.recognizeText(in: image, accuracy: accuracy), !text.isBlank else {
                presentError("No readable text found on screen.")
                return
            }

            await contextStore.appendOCR(OCRSnapshot(text: text))
            pendingQuestion = text
            await requestAI(
                force: true,
                skipSummarization: true,
                interruptCurrent: true,
                displayQuestion: text,
                userOverride: """
                Screen capture mode. Solve the problem shown on screen using the OCR text below.
                Speak the answer like an interview explanation (first person, conversational), with markdown
                examples/code when useful. Light everyday grammar is fine; keep technical terms precise.

                If this is an algorithm/coding/DSA problem: give multiple solution variations when possible
                (typically 2–3) — brute force, optimal, and an alternate/tradeoff when useful.

                OCR:
                \(text)
                """
            )
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func setClickThrough(_ enabled: Bool) {
        isClickThrough = enabled
        settingsStore.update { $0.clickThroughEnabled = enabled }
    }

    func setPositionLocked(_ locked: Bool) {
        isPositionLocked = locked
        settingsStore.update { $0.positionLocked = locked }
    }

    // MARK: - Private

    private func ensureSpeechRunning(markSpeechOnly: Bool) async throws {
        if speech.isEngineRunning {
            if markSpeechOnly { speechOnlyMode = true }
            return
        }

        let settings = settingsStore.settings
        try await speech.start(
            microphoneUID: settings.selectedMicrophoneUID,
            pauseSeconds: settings.pauseDetectionSeconds,
            apiKey: settingsStore.apiKey
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleSpeechEvent(event)
            }
        }
        if isMicMuted {
            await speech.setMuted(true)
        }
        if markSpeechOnly {
            speechOnlyMode = true
        }
    }

    private func handleSpeechEvent(_ event: SpeechEvent) {
        // Stream VAD events only — Whisper uses manual capture + Send.
        guard settingsStore.settings.assistantMode == .stream else { return }
        guard isRunning || speech.isEngineRunning, status != .paused else { return }

        switch event.kind {
        case .partial(let text):
            liveTranscript = text
            // Never bounce status away from an in-flight answer.
            guard status != .thinking, status != .streaming else { return }
            if isListenArmed || status == .listening {
                status = .listening
            } else if case .error = status {
                status = .listening
            }
        case .final(let text):
            guard !isMicMuted else { return }
            // Candidate reading the on-screen answer aloud ≠ a new interview question.
            if isCandidateReadingAnswer(text) {
                liveTranscript = "You (reading answer) — ignored as a new question"
                pendingQuestion = ""
                AppLog.speech.info("Ignored transcript that matches on-screen answer")
                return
            }
            liveTranscript = text
            pendingQuestion = text
            Task {
                await contextStore.appendTranscript(TranscriptChunk(text: text, isFinal: true))
            }
        case .pauseDetected:
            // Mute never starts an answer. Start Session keeps the mic for context only —
            // answers require Listen (or an explicit Submit / typed ask).
            guard !isMicMuted else { return }
            let question = (pendingQuestion.isBlank ? liveTranscript : pendingQuestion)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if isCandidateReadingAnswer(question) || question.hasPrefix("You (reading answer)") {
                // Stay armed so the real next interviewer question still works.
                liveTranscript = "You (reading answer) — still listening for the next question"
                pendingQuestion = ""
                return
            }

            if isGeneratingAnswer || status == .thinking || status == .streaming {
                // Only queue if the user re-armed Listen for the next turn.
                if answerOnNextPause || isListenArmed {
                    queueNextQuestionIfAppropriate(question, userInitiated: true)
                    answerOnNextPause = false
                    isListenArmed = false
                    if speechOnlyMode {
                        stopSpeechAfterAnswer = true
                    }
                }
                return
            }

            Task { @MainActor in
                guard !self.isMicMuted else { return }
                guard !self.isGeneratingAnswer, self.status != .thinking, self.status != .streaming else {
                    if self.answerOnNextPause || self.isListenArmed {
                        self.queueNextQuestionIfAppropriate(question, userInitiated: true)
                    }
                    return
                }
                guard self.answerOnNextPause else { return }

                let spoken = (self.pendingQuestion.isBlank ? self.liveTranscript : self.pendingQuestion)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if self.isCandidateReadingAnswer(spoken) {
                    self.liveTranscript = "You (reading answer) — still listening for the next question"
                    self.pendingQuestion = ""
                    return
                }

                self.answerOnNextPause = false
                self.isListenArmed = false
                if self.speechOnlyMode {
                    self.stopSpeechAfterAnswer = true
                }
                await self.requestAI(
                    force: true,
                    skipSummarization: true,
                    interruptCurrent: false,
                    displayQuestion: spoken,
                    userOverride: Self.speechAnswerOverride(for: spoken)
                )
            }
        case .error(let message):
            lastErrorMessage = message
            AppLog.speech.error("Speech error: \(message)")
        }
    }

    /// - Parameter userInitiated: true for Listen / Submit / typed ask. Ambient pauses must not queue.
    private func queueNextQuestionIfAppropriate(_ question: String, userInitiated: Bool) {
        guard userInitiated else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fingerprint = trimmed.normalizedForComparison()
        guard fingerprint != lastQuestionFingerprint else { return }
        if let queued = queuedNextQuestion,
           queued.normalizedForComparison() == fingerprint {
            return
        }
        queuedNextQuestion = trimmed
        AppLog.speech.info("Queued next question while answering (\(trimmed.prefix(60)))")
    }

    private func drainQueuedQuestionIfNeeded() async {
        guard let queued = queuedNextQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !queued.isEmpty else {
            queuedNextQuestion = nil
            return
        }
        queuedNextQuestion = nil
        pendingQuestion = queued
        liveTranscript = queued
        allowAIWithoutFullSession = true
        await requestAI(
            force: true,
            skipSummarization: true,
            interruptCurrent: false,
            displayQuestion: queued,
            userOverride: Self.speechAnswerOverride(for: queued)
        )
    }

    /// True when the mic heard the candidate reading Smarty's answer, not a new interviewer question.
    func isCandidateReadingAnswer(_ transcript: String) -> Bool {
        var answers = answeredTurns.flatMap { [$0.technicalAnswer, $0.friendlyAnswer] }
        answers.append(currentAnswer)
        return CandidateSpeechClassifier.isReadingProvidedAnswer(
            transcript: transcript,
            answers: answers.filter { !$0.isBlank }
        )
    }

    private static func speechAnswerOverride(for transcript: String) -> String {
        """
        Answer the interviewer's NEW question from this speech transcript as spoken interview words —
        natural first-person explanation I can read aloud. Use markdown for examples/code when useful.
        Everyday grammar can be light; technical terms must stay accurate.

        The candidate may read your previous answer aloud from their screen — that is NOT a new question
        (the app filters obvious cases). Treat this transcript as the interviewer's question only.

        Infer ASR mistakes (e.g. "active fiber" / "virtual" → React Fiber vs Virtual DOM).

        Transcript:
        \(transcript)
        """
    }

    private func handleFrame(_ image: CGImage) async {
        guard isRunning, status != .paused else { return }
        // Passive OCR context only — never auto-answer from the screen (that stole focus from speech).
        do {
            if let text = try await ocr.recognizeText(in: image, accuracy: .fast) {
                await contextStore.appendOCR(OCRSnapshot(text: text))
            }
        } catch {
            AppLog.ocr.error("OCR failed: \(error.localizedDescription)")
        }
    }

    /// - Parameter interruptCurrent: only user-explicit actions may cancel an in-flight request.
    private func requestAI(
        force: Bool,
        skipSummarization: Bool,
        interruptCurrent: Bool = false,
        replaceLatestTurn: Bool = false,
        displayQuestion: String? = nil,
        userOverride: String? = nil,
        images: [ImageAttachment] = []
    ) async {
        let canRun = isRunning || allowAIWithoutFullSession
        guard canRun, status != .paused else { return }
        guard settingsStore.hasAPIKey else {
            presentError("Add your OpenAI API key in Settings.")
            return
        }

        // Hard gate: background speech/OCR must never cancel a live answer.
        if isGeneratingAnswer || status == .thinking || status == .streaming {
            guard interruptCurrent else { return }
        }

        let settings = settingsStore.settings
        let now = Date()
        if !force, now.timeIntervalSince(lastRequestAt) < settings.minRequestInterval {
            return
        }

        let spokenSeed = [pendingQuestion, liveTranscript].first { !$0.isBlank } ?? ""
        let questionSeed = userOverride ?? spokenSeed
        let fingerprint = questionSeed.normalizedForComparison()
        let turnQuestion = (displayQuestion ?? spokenSeed)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !force, fingerprint.isBlank, images.isEmpty {
            return
        }
        if !force, fingerprint == lastQuestionFingerprint, images.isEmpty {
            return
        }

        if interruptCurrent {
            streamTask?.cancel()
            streamTask = nil
            summarizeTask?.cancel()
            keyTermsTask?.cancel()
        }
        let generationID = UUID()
        activeGenerationID = generationID
        isGeneratingAnswer = true
        replaceLatestTurnOnFinish = replaceLatestTurn
        inFlightDisplayQuestion = turnQuestion.isEmpty
            ? (answeredTurns.last?.question ?? "Question")
            : turnQuestion
        lastQuestionFingerprint = fingerprint
        lastRequestAt = now
        keyTerms = []
        status = .thinking

        // Summarization never blocks the hot path.
        if skipSummarization {
            summarizeTask = Task { [weak self] in
                guard let self else { return }
                await self.summarizer.summarizeIfNeeded(
                    apiKey: self.settingsStore.apiKey,
                    model: settings.model,
                    store: self.contextStore,
                    maxTokens: settings.maxContextTokens
                )
            }
        }

        // Lean input only — no await on full context snapshot before the fast technical call.
        let leanQuestion = turnQuestion.isEmpty ? "Answer the interview question." : turnQuestion
        let leanInput = TokenEstimator.truncateToTokenBudget(
            userOverride ?? leanQuestion,
            maxTokens: 900
        )
        await contextStore.appendUser(questionSeed.isBlank ? leanQuestion : questionSeed)
        guard activeGenerationID == generationID, isGeneratingAnswer else { return }

        let sessionGuidance = PromptBuilder.sessionGuidance(
            language: settings.preferredProgrammingLanguage,
            focus: settings.interviewFocus,
            length: settings.answerLength
        )
        let technicalInstructions = Self.technicalSpokenInstructions + "\n\n" + sessionGuidance

        let fastModel = settings.model.hasPrefix("gpt-4o") ? settings.model : "gpt-4o-mini"
        let technicalRequest = OpenAIRequest(
            model: fastModel,
            instructions: technicalInstructions,
            input: leanInput,
            temperature: min(settings.temperature, 0.55),
            stream: false,
            images: images
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard self.activeGenerationID == generationID else { return }
                // 1) Technical spoken answer — show ASAP (no pause for friendly / key terms).
                let technical = try await self.openAI.complete(
                    apiKey: self.settingsStore.apiKey,
                    request: technicalRequest
                )
                try Task.checkCancellation()
                guard self.activeGenerationID == generationID else { return }
                let turnID = await self.publishTechnicalAnswer(technical, generationID: generationID)

                // 2) Friendly answer in a second call (does not delay the first paint).
                let friendlyRequest = OpenAIRequest(
                    model: fastModel,
                    instructions: Self.friendlyExplainInstructions,
                    input: """
                    Interview question:
                    \(leanQuestion)

                    Technical spoken answer already shown to the candidate:
                    \(technical.trimmed)
                    """,
                    temperature: 0.45,
                    stream: false
                )
                let friendly = try await self.openAI.complete(
                    apiKey: self.settingsStore.apiKey,
                    request: friendlyRequest
                )
                try Task.checkCancellation()
                guard self.activeGenerationID == generationID else { return }
                await self.publishFriendlyAnswer(friendly, turnID: turnID, generationID: generationID)

                // 3) Key terms last (never blocks answers).
                self.refreshKeyTerms(from: technical, generationID: generationID)
            } catch is CancellationError {
                if self.activeGenerationID == generationID {
                    self.recoverStatusAfterInterrupt()
                }
            } catch let error as OpenAIError {
                if self.activeGenerationID == generationID {
                    self.presentError(error.localizedDescription)
                }
            } catch {
                if self.activeGenerationID == generationID {
                    self.presentError(error.localizedDescription)
                }
            }
        }
    }

    private func takePendingImages() -> [ImageAttachment] {
        let images = pendingImages
        pendingImages = []
        return images
    }

    private func ingestAttachedImageOCR(_ images: [ImageAttachment]) async {
        guard !images.isEmpty else { return }
        for attachment in images {
            guard let cgImage = attachment.makeCGImage() else { continue }
            do {
                if let text = try await ocr.recognizeText(in: cgImage, accuracy: .accurate), !text.isBlank {
                    await contextStore.appendOCR(OCRSnapshot(text: text))
                }
            } catch {
                AppLog.ocr.error("Attachment OCR failed: \(error.localizedDescription)")
            }
        }
    }

    private static let technicalSpokenInstructions = """
    You are a discreet interview assistant. Reply with ONE spoken technical answer the candidate can read aloud.
    First person. Natural interview cadence. Precise technical terms. Markdown/code only when needed.
    Keep it tight — about 30–60 seconds of speech. No second “simple” version. No preamble.
    For coding/DSA: prefer the optimal approach first with brief complexity; one short code block if useful.
    Do not invent employers, metrics, or tools not implied by the question.

    \(InlineTechnicalExplanationFormat.rules)
    """

    private static let friendlyExplainInstructions = """
    Rewrite the idea into a short human-friendly explanation for the candidate (not for reading aloud to the interviewer).
    Plain language, no textbook tone, no jargon walls. Use a quick analogy if it helps.
    4–8 short sentences or a tiny bullet list max. No code unless essential. No “as an AI”.
    If you must keep a technical term, still use the mandatory pattern **TERM** **[simple explanation]** on first use.

    \(InlineTechnicalExplanationFormat.rules)
    """

    /// Publishes the fast technical answer immediately. Returns the turn id for the friendly follow-up.
    @discardableResult
    private func publishTechnicalAnswer(_ text: String, generationID: UUID) async -> UUID? {
        guard activeGenerationID == generationID else { return nil }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else {
            presentError(OpenAIError.emptyResponse.localizedDescription)
            return nil
        }

        currentAnswer = trimmed
        let question = inFlightDisplayQuestion.isEmpty ? "Question" : inFlightDisplayQuestion
        let turnID: UUID
        if replaceLatestTurnOnFinish, !answeredTurns.isEmpty {
            let last = answeredTurns[answeredTurns.count - 1]
            turnID = last.id
            answeredTurns[answeredTurns.count - 1] = AnswerTurn(
                id: last.id,
                index: last.index,
                question: question,
                technicalAnswer: trimmed,
                friendlyAnswer: "",
                createdAt: Date()
            )
        } else {
            let nextIndex = (answeredTurns.last?.index ?? 0) + 1
            let turn = AnswerTurn(
                index: nextIndex,
                question: question,
                technicalAnswer: trimmed,
                friendlyAnswer: ""
            )
            turnID = turn.id
            answeredTurns.append(turn)
        }
        replaceLatestTurnOnFinish = false

        await contextStore.appendAssistant(trimmed)
        history.append(ConversationMessage(role: .assistant, content: trimmed))
        settingsStore.recentHistory = history
        allowAIWithoutFullSession = false

        // Unlock UI immediately — friendly fills in below without blocking Send / Listen.
        if activeGenerationID == generationID {
            isGeneratingAnswer = false
        }
        status = (isRunning || speech.isEngineRunning || isWhisperRecording || isWhisperRecordingPaused)
            ? .listening
            : .idle

        if queuedNextQuestion != nil {
            await drainQueuedQuestionIfNeeded()
        } else {
            await endSpeechOnlyIfNeeded()
        }
        return turnID
    }

    private func publishFriendlyAnswer(_ text: String, turnID: UUID?, generationID: UUID) async {
        guard activeGenerationID == generationID, let turnID else { return }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        guard let idx = answeredTurns.firstIndex(where: { $0.id == turnID }) else { return }
        var turn = answeredTurns[idx]
        turn.friendlyAnswer = trimmed
        answeredTurns[idx] = turn
    }

    private func endSpeechOnlyIfNeeded() async {
        guard stopSpeechAfterAnswer else { return }
        guard queuedNextQuestion == nil else { return }
        stopSpeechAfterAnswer = false
        speechOnlyMode = false
        await speech.stop()
        isRunning = false
    }

    private func refreshKeyTerms(from answer: String, generationID: UUID) {
        keyTermsTask?.cancel()
        keyTermsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let cards = try await self.extractKeyTerms(from: answer)
                guard !Task.isCancelled, self.activeGenerationID == generationID else { return }
                self.keyTerms = cards
            } catch {
                AppLog.openai.error("Key terms extraction failed: \(error.localizedDescription)")
            }
        }
    }

    private func extractKeyTerms(from answer: String) async throws -> [KeyTermCard] {
        let snippet = TokenEstimator.truncateToTokenBudget(answer, maxTokens: 1200)
        let raw = try await openAI.complete(
            apiKey: settingsStore.apiKey,
            request: OpenAIRequest(
                model: settingsStore.settings.model,
                instructions: """
                Extract 3–6 important technical terms from the interview answer.
                Return ONLY a JSON array (no markdown) of objects:
                [{"term":"...","definition":"simple technical definition in 1–2 sentences","relatedQuestions":["possible follow-up Q1","Q2"]}]
                Definitions must be accurate but easy. Prefer terms a candidate might be asked about next.
                """,
                input: snippet,
                temperature: 0.2,
                stream: false
            )
        )
        return KeyTermCard.parse(from: raw)
    }

    private func recoverStatusAfterInterrupt() {
        isGeneratingAnswer = false
        replaceLatestTurnOnFinish = false
        if stopSpeechAfterAnswer, queuedNextQuestion == nil {
            stopSpeechAfterAnswer = false
            speechOnlyMode = false
            isRunning = false
            Task { await speech.stop() }
            status = .idle
            return
        }
        if isRunning || speech.isEngineRunning {
            status = .listening
        } else {
            status = .idle
        }
    }


    private func presentError(_ message: String) {
        isGeneratingAnswer = false
        replaceLatestTurnOnFinish = false
        status = .error(message)
        lastErrorMessage = message
        allowAIWithoutFullSession = false
        recoverTask?.cancel()
        recoverTask = Task { [weak self] in
            try? await Task.sleep(seconds: 1.5)
            guard let self, !Task.isCancelled else { return }
            if case .error = self.status {
                self.recoverStatusAfterInterrupt()
            }
        }
    }

    static let screenRecordingHelpMessage = """
        Screen Recording isn’t active for this process yet (speech still works). Stop Smarty in Xcode, run: tccutil reset ScreenCapture com.smarty.app — then remove any Smarty rows in System Settings → Privacy & Security → Screen Recording, Run again, enable the new Smarty, Stop, and Run once more.
        """
}
