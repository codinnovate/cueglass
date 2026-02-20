import Foundation

/// Pure flush/pause policy for mic capture — unit-tested without AVAudioEngine.
struct SpeechEndpointing: Sendable {
    enum Action: Equatable, Sendable {
        case wait
        case flush
    }

    var silence: SilenceDetector
    /// Minimum buffered audio before a pause may flush.
    var minBufferSeconds: TimeInterval = 0.35
    /// Flush even without a clean pause once we have real activity.
    var forceFlushSeconds: TimeInterval = 4.5
    /// Absolute cap so a stuck VAD cannot hold forever.
    var hardCapSeconds: TimeInterval = 7.0
    var minFlushGapSeconds: TimeInterval = 0.5

    private var lastFlushAt: Date = .distantPast

    init(pauseThresholdSeconds: TimeInterval = 0.75) {
        silence = SilenceDetector(pauseThresholdSeconds: pauseThresholdSeconds)
    }

    mutating func resetSilenceArm() {
        silence.resetAfterTrigger()
    }

    mutating func evaluate(
        rms: Float,
        bufferSeconds: TimeInterval,
        now: Date = Date(),
        isTranscribing: Bool = false,
        isMuted: Bool = false
    ) -> Action {
        guard !isTranscribing, !isMuted else { return .wait }

        let paused = silence.update(rms: rms, now: now)

        if bufferSeconds < minBufferSeconds {
            return .wait
        }
        if now.timeIntervalSince(lastFlushAt) < minFlushGapSeconds {
            return .wait
        }

        let force =
            (silence.hasHeardSpeech && bufferSeconds >= forceFlushSeconds)
            || (silence.hadActivity && bufferSeconds >= forceFlushSeconds)
            || (bufferSeconds >= hardCapSeconds && (silence.hadActivity || silence.peakRms >= 0.008))

        guard paused || force else { return .wait }

        lastFlushAt = now
        return .flush
    }
}
