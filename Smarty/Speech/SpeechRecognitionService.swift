import AVFoundation
import Foundation

struct SpeechEvent: Sendable {
    enum Kind: Sendable {
        case partial(String)
        case final(String)
        case pauseDetected
        case error(String)
    }

    let kind: Kind
}

protocol SpeechRecognizing: AnyObject, Sendable {
    var isEngineRunning: Bool { get }
    var isMuted: Bool { get }
    /// True while Whisper manual capture has buffered enough audio to send.
    var hasManualCaptureAudio: Bool { get }
    func availableMicrophones() async -> [MicrophoneInfo]
    func start(
        microphoneUID: String?,
        pauseSeconds: TimeInterval,
        apiKey: String,
        handler: @escaping @Sendable (SpeechEvent) -> Void
    ) async throws
    func stop() async
    func setMuted(_ muted: Bool) async

    /// Mic tap only — no VAD / pause detection (Whisper mode).
    func startManualCapture(microphoneUID: String?, apiKey: String) async throws
    func pauseManualCapture() async
    func resumeManualCapture() async
    func cancelManualCapture() async
    func finishManualCaptureAndTranscribe() async throws -> String
}

/// Mic capture + local VAD, transcription via OpenAI STT (gpt-4o-mini-transcribe / whisper-1).
final class SpeechRecognitionService: SpeechRecognizing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.smarty.speech", qos: .userInitiated)
    private let audioEngine = AVAudioEngine()
    private let transcriber: any OpenAIClienting
    private var endpointing = SpeechEndpointing()
    private var silenceTimer: DispatchSourceTimer?
    private var handler: (@Sendable (SpeechEvent) -> Void)?
    private var shouldKeepListening = false
    private var isManualMode = false
    private var isTranscribing = false
    private var apiKey: String = ""
    private var sampleRate: Double = 16_000
    private let pcmBox = PCMBox()
    private let rmsBox = RMSBox()
    private let stateLock = NSLock()
    private var _isEngineRunning = false
    private let muteFlag = MuteFlag()
    /// When true, audio tap skips appending (manual pause).
    private let capturePausedFlag = MuteFlag()
    private var committedText = ""

    init(transcriber: any OpenAIClienting = OpenAIClient()) {
        self.transcriber = transcriber
    }

    var isEngineRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isEngineRunning
    }

    var isMuted: Bool { muteFlag.value }

    var hasManualCaptureAudio: Bool {
        Double(pcmBox.sampleCount) / max(sampleRate, 1) >= 0.15
    }

    private func setEngineRunning(_ value: Bool) {
        stateLock.lock(); _isEngineRunning = value; stateLock.unlock()
    }

    func availableMicrophones() async -> [MicrophoneInfo] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[MicrophoneInfo], Never>) in
            queue.async {
                let devices = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone, .external],
                    mediaType: .audio,
                    position: .unspecified
                ).devices.map {
                    MicrophoneInfo(id: $0.uniqueID, name: $0.localizedName)
                }
                continuation.resume(returning: devices)
            }
        }
    }

    func start(
        microphoneUID: String?,
        pauseSeconds: TimeInterval,
        apiKey: String,
        handler: @escaping @Sendable (SpeechEvent) -> Void
    ) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechError.missingAPIKey
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    self.stopSync()
                    try self.startSync(
                        microphoneUID: microphoneUID,
                        pauseSeconds: pauseSeconds,
                        apiKey: apiKey,
                        handler: handler
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.stopSync()
                continuation.resume()
            }
        }
    }

    func setMuted(_ muted: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.muteFlag.value = muted
                if muted {
                    self.pcmBox.clear()
                    self.endpointing.resetSilenceArm()
                    self.handler?(.init(kind: .partial("Mic muted")))
                } else if self.shouldKeepListening {
                    self.handler?(.init(kind: .partial(
                        self.committedText.isEmpty ? "Listening… (OpenAI STT)" : self.committedText
                    )))
                }
                continuation.resume()
            }
        }
    }

    func startManualCapture(microphoneUID: String?, apiKey: String) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechError.missingAPIKey
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    self.stopSync()
                    try self.startManualSync(microphoneUID: microphoneUID, apiKey: apiKey)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func pauseManualCapture() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.capturePausedFlag.value = true
                continuation.resume()
            }
        }
    }

    func resumeManualCapture() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard self.isManualMode else {
                    continuation.resume()
                    return
                }
                self.capturePausedFlag.value = false
                continuation.resume()
            }
        }
    }

    func cancelManualCapture() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.stopSync()
                continuation.resume()
            }
        }
    }

    func finishManualCaptureAndTranscribe() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                guard self.isManualMode else {
                    continuation.resume(throwing: SpeechError.unavailable)
                    return
                }
                let samples = self.pcmBox.drain()
                let minSamples = Int(self.sampleRate * 0.15)
                guard samples.count > minSamples else {
                    continuation.resume(throwing: SpeechError.emptyCapture)
                    return
                }
                let wav = WavEncoder.makeWav(samples: samples, sampleRate: self.sampleRate)
                let apiKey = self.apiKey
                let prompt = Self.sttPrompt
                let transcriber = self.transcriber
                // Tear down mic while STT runs.
                self.stopSync()

                Task {
                    do {
                        let text = try await transcriber.transcribeAudio(
                            apiKey: apiKey,
                            wavData: wav,
                            prompt: prompt
                        )
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            continuation.resume(throwing: SpeechError.emptyCapture)
                        } else {
                            continuation.resume(returning: trimmed)
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func startSync(
        microphoneUID: String?,
        pauseSeconds: TimeInterval,
        apiKey: String,
        handler: @escaping @Sendable (SpeechEvent) -> Void
    ) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        self.apiKey = apiKey
        self.handler = handler
        self.shouldKeepListening = true
        self.isManualMode = false
        self.isTranscribing = false
        self.muteFlag.value = false
        self.capturePausedFlag.value = false
        self.committedText = ""
        self.pcmBox.clear()
        endpointing = SpeechEndpointing(
            pauseThresholdSeconds: max(0.5, min(pauseSeconds, 1.4))
        )

        try installTapAndStartEngine(microphoneUID: microphoneUID)
        startSilenceTimer()
        handler(.init(kind: .partial("Listening… (OpenAI STT)")))
        AppLog.speech.info("OpenAI STT listening started @ \(self.sampleRate)Hz")
    }

    private func startManualSync(microphoneUID: String?, apiKey: String) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        self.apiKey = apiKey
        self.handler = nil
        self.shouldKeepListening = false
        self.isManualMode = true
        self.isTranscribing = false
        self.muteFlag.value = false
        self.capturePausedFlag.value = false
        self.committedText = ""
        self.pcmBox.clear()

        try installTapAndStartEngine(microphoneUID: microphoneUID)
        AppLog.speech.info("Whisper manual capture started @ \(self.sampleRate)Hz")
    }

    private func installTapAndStartEngine(microphoneUID: String?) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        if let microphoneUID,
           let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
           ).devices.first(where: { $0.uniqueID == microphoneUID }) {
            AppLog.speech.info("Using preferred microphone: \(device.localizedName)")
        }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw SpeechError.invalidAudioFormat
        }
        sampleRate = hardwareFormat.sampleRate

        let pcmBox = self.pcmBox
        let rmsBox = self.rmsBox
        let muteFlag = self.muteFlag
        let capturePausedFlag = self.capturePausedFlag
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { buffer, _ in
            if muteFlag.value || capturePausedFlag.value {
                rmsBox.value = 0
                return
            }
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }

            var sum: Float = 0
            var floats = [Float](repeating: 0, count: count)
            let strideN = max(1, Int((hardwareFormat.sampleRate / 16_000.0).rounded()))
            var out: [Float] = []
            out.reserveCapacity(count / strideN + 1)
            for i in 0..<count {
                let sample = channel[i]
                floats[i] = sample
                sum += sample * sample
                if i % strideN == 0 {
                    out.append(sample)
                }
            }
            rmsBox.value = sqrt(sum / Float(count))
            pcmBox.append(out.isEmpty ? floats : out)
        }

        sampleRate = hardwareFormat.sampleRate / Double(max(1, Int((hardwareFormat.sampleRate / 16_000.0).rounded())))

        audioEngine.prepare()
        try audioEngine.start()
        setEngineRunning(true)
    }

    private func stopSync() {
        dispatchPrecondition(condition: .onQueue(queue))
        shouldKeepListening = false
        isManualMode = false
        capturePausedFlag.value = false
        setEngineRunning(false)
        silenceTimer?.cancel()
        silenceTimer = nil
        handler = nil
        apiKey = ""
        committedText = ""
        pcmBox.clear()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        rmsBox.value = 0
    }

    private func startSilenceTimer() {
        silenceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.12, repeating: 0.12)
        timer.setEventHandler { [weak self] in
            self?.checkSilence()
        }
        silenceTimer = timer
        timer.resume()
    }

    private func checkSilence() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard shouldKeepListening else { return }

        let seconds = Double(pcmBox.sampleCount) / max(sampleRate, 1)
        let action = endpointing.evaluate(
            rms: rmsBox.value,
            bufferSeconds: seconds,
            now: Date(),
            isTranscribing: isTranscribing,
            isMuted: isMuted
        )

        switch action {
        case .wait:
            if endpointing.silence.hasHeardSpeech, seconds > 0.3 {
                let preview = committedText.isEmpty
                    ? "Listening… \(String(format: "%.0f", seconds))s — pause when done"
                    : committedText
                handler?(.init(kind: .partial(preview)))
            } else if seconds > 1.0 {
                handler?(.init(kind: .partial("Listening… (waiting for speech)")))
            }
        case .flush:
            flushAndTranscribe()
        }
    }

    private func flushAndTranscribe() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !isTranscribing else { return }

        let samples = pcmBox.drain()
        let minSamples = Int(sampleRate * 0.28)
        guard samples.count > minSamples else {
            if !samples.isEmpty { pcmBox.append(samples) }
            return
        }

        endpointing.resetSilenceArm()
        isTranscribing = true
        handler?(.init(kind: .partial(committedText.isEmpty ? "Transcribing…" : "\(committedText) …")))

        let wav = WavEncoder.makeWav(samples: samples, sampleRate: sampleRate)
        let apiKey = self.apiKey
        let prompt = Self.sttPrompt
        let transcriber = self.transcriber

        Task { [weak self] in
            do {
                let text = try await transcriber.transcribeAudio(
                    apiKey: apiKey,
                    wavData: wav,
                    prompt: prompt
                )
                await self?.handleTranscription(text)
            } catch {
                await self?.handleTranscriptionError(error)
            }
        }
    }

    private func handleTranscription(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                defer {
                    self.isTranscribing = false
                    continuation.resume()
                }
                guard self.shouldKeepListening, !self.isMuted else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Empty STT used to drop pauseDetected and leave Listen stuck forever.
                guard !trimmed.isEmpty else {
                    self.committedText = ""
                    self.handler?(.init(kind: .partial("No speech caught — speak the question, then pause")))
                    AppLog.speech.info("OpenAI STT returned empty — still listening")
                    return
                }

                self.committedText = trimmed
                self.handler?(.init(kind: .final(trimmed)))
                self.handler?(.init(kind: .pauseDetected))
                // Fresh utterance next time — don't glue interviewer + candidate reading.
                self.committedText = ""
                AppLog.speech.info("OpenAI STT: \(trimmed.prefix(80))")
            }
        }
    }

    private func handleTranscriptionError(_ error: Error) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.isTranscribing = false
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.handler?(.init(kind: .error("STT: \(message)")))
                AppLog.speech.error("OpenAI STT failed: \(message)")
                continuation.resume()
            }
        }
    }

    private static let sttPrompt = """
    Technical interview audio. Likely terms: React, React Fiber, Virtual DOM, JavaScript, TypeScript, \
    hooks, useEffect, Node.js, algorithms, Big O, system design, API, SQL, Swift, Python.
    """
}

enum SpeechError: LocalizedError {
    case unavailable
    case invalidAudioFormat
    case missingAPIKey
    case emptyCapture

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Speech recognition is unavailable."
        case .invalidAudioFormat:
            return "Microphone audio format is unavailable. Check System Settings → Sound → Input."
        case .missingAPIKey:
            return "OpenAI API key required for speech-to-text."
        case .emptyCapture:
            return "No speech recorded — hold the mic a bit longer, then Send."
        }
    }
}

enum WavEncoder {
    static func makeWav(samples: [Float], sampleRate: Double) -> Data {
        let int16 = samples.map { sample -> Int16 in
            let clipped = max(-1, min(1, sample))
            return Int16(clipped * Float(Int16.max))
        }
        let dataSize = int16.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func append(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 2))
        }
        func appendUInt32(_ value: UInt32) {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 4))
        }

        let rate = UInt32(max(1, sampleRate.rounded()))
        append("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(rate)
        appendUInt32(rate * 2)
        appendUInt16(2)
        appendUInt16(16)
        append("data")
        appendUInt32(UInt32(dataSize))
        int16.withUnsafeBufferPointer { ptr in
            data.append(Data(buffer: ptr))
        }
        return data
    }
}

private final class PCMBox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let maxSamples = 16_000 * 25

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    func append(_ chunk: [Float]) {
        lock.lock()
        samples.append(contentsOf: chunk)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        let out = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        return out
    }

    func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

private final class RMSBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Float = 0
    var value: Float {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

private final class MuteFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
