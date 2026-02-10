import Foundation

/// Adaptive VAD: learns ambient noise, arms on real speech, and reports pauses.
struct SilenceDetector: Sendable {
    var pauseThresholdSeconds: TimeInterval
    var minSpeechFloor: Float
    var speechMultiplier: Float
    var speechMargin: Float

    private(set) var noiseFloor: Float = 0.003
    private(set) var speechPeak: Float = 0
    private(set) var lastSpeechAt: Date?
    private(set) var hasHeardSpeech: Bool = false
    /// Any energy above a low activity floor (used for force-flush safety).
    private(set) var hadActivity: Bool = false
    private(set) var peakRms: Float = 0
    private var startedAt: Date?
    private var calibrated = false

    var speechFloor: Float {
        get { minSpeechFloor }
        set { minSpeechFloor = newValue }
    }

    init(
        pauseThresholdSeconds: TimeInterval = 0.75,
        speechFloor: Float = 0.01,
        speechMultiplier: Float = 2.2,
        speechMargin: Float = 0.005
    ) {
        self.pauseThresholdSeconds = pauseThresholdSeconds
        self.minSpeechFloor = speechFloor
        self.speechMultiplier = speechMultiplier
        self.speechMargin = speechMargin
    }

    var speechGate: Float {
        max(minSpeechFloor, noiseFloor * speechMultiplier + speechMargin)
    }

    var activityFloor: Float {
        max(0.006, noiseFloor * 1.35 + 0.002)
    }

    mutating func skipCalibration(noiseFloor seed: Float = 0.003) {
        noiseFloor = max(0.001, seed)
        calibrated = true
        startedAt = Date()
    }

    mutating func update(rms: Float, now: Date = Date()) -> Bool {
        if startedAt == nil { startedAt = now }
        peakRms = max(peakRms, rms)

        if !calibrated {
            noiseFloor = noiseFloor * 0.65 + max(0, rms) * 0.35
            if let startedAt, now.timeIntervalSince(startedAt) >= 0.55 {
                calibrated = true
                noiseFloor = max(0.001, min(noiseFloor, 0.05))
            }
            return false
        }

        if rms >= activityFloor {
            hadActivity = true
        }

        let gate = speechGate
        if rms >= gate {
            markSpeech(now: now)
            speechPeak = max(speechPeak * 0.88, rms)
            return false
        }

        // Hangover: brief dips during words shouldn't end the utterance.
        if hasHeardSpeech, let lastSpeechAt,
           now.timeIntervalSince(lastSpeechAt) < 0.18,
           rms >= activityFloor {
            return false
        }

        noiseFloor = noiseFloor * 0.92 + max(0, rms) * 0.08
        noiseFloor = max(0.001, min(noiseFloor, 0.07))

        return isPaused(now: now)
    }

    mutating func markSpeech(now: Date = Date()) {
        hasHeardSpeech = true
        hadActivity = true
        lastSpeechAt = now
        calibrated = true
    }

    func isPaused(now: Date = Date()) -> Bool {
        guard hasHeardSpeech, let lastSpeechAt else { return false }
        return now.timeIntervalSince(lastSpeechAt) >= pauseThresholdSeconds
    }

    mutating func resetAfterTrigger() {
        hasHeardSpeech = false
        lastSpeechAt = nil
        speechPeak = 0
        hadActivity = false
        peakRms = 0
    }

    mutating func updateThreshold(_ seconds: TimeInterval) {
        pauseThresholdSeconds = max(0.35, seconds)
    }
}
