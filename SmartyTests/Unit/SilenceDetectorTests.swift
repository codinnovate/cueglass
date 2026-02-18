import XCTest
@testable import Smarty

final class SilenceDetectorTests: XCTestCase {
    func testNoPauseWithoutPriorSpeech() {
        var detector = SilenceDetector(pauseThresholdSeconds: 0.5, speechFloor: 0.02)
        detector.skipCalibration(noiseFloor: 0.003)
        let now = Date()
        XCTAssertFalse(detector.update(rms: 0.001, now: now))
        XCTAssertFalse(detector.update(rms: 0.0, now: now.addingTimeInterval(1)))
    }

    func testSpeechThenPause() {
        var detector = SilenceDetector(pauseThresholdSeconds: 0.5, speechFloor: 0.02)
        detector.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        XCTAssertFalse(detector.update(rms: 0.05, now: t0))
        XCTAssertTrue(detector.hasHeardSpeech)
        // Hangover window (~0.18s) must not pause yet.
        XCTAssertFalse(detector.update(rms: 0.0, now: t0.addingTimeInterval(0.1)))
        XCTAssertTrue(detector.update(rms: 0.0, now: t0.addingTimeInterval(0.6)))
    }

    func testResetAfterTriggerClearsArm() {
        var detector = SilenceDetector(pauseThresholdSeconds: 0.3, speechFloor: 0.02)
        detector.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        _ = detector.update(rms: 0.05, now: t0)
        XCTAssertTrue(detector.update(rms: 0.0, now: t0.addingTimeInterval(0.4)))
        detector.resetAfterTrigger()
        XCTAssertFalse(detector.hasHeardSpeech)
        XCTAssertFalse(detector.hadActivity)
        XCTAssertFalse(detector.update(rms: 0.0, now: t0.addingTimeInterval(1.0)))
    }

    func testThresholdUpdate() {
        var detector = SilenceDetector(pauseThresholdSeconds: 1.0, speechFloor: 0.02)
        detector.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        _ = detector.update(rms: 0.05, now: t0)
        detector.updateThreshold(0.2)
        XCTAssertEqual(detector.pauseThresholdSeconds, 0.35, accuracy: 0.0001)
        XCTAssertTrue(detector.update(rms: 0.0, now: t0.addingTimeInterval(0.4)))
    }

    func testTranscriptActivityThenIdlePause() {
        var detector = SilenceDetector(pauseThresholdSeconds: 0.4, speechFloor: 0.02)
        detector.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        detector.markSpeech(now: t0)
        XCTAssertFalse(detector.isPaused(now: t0.addingTimeInterval(0.2)))
        XCTAssertTrue(detector.isPaused(now: t0.addingTimeInterval(0.5)))
    }

    func testWeakAmbientDoesNotResetIdleClock() {
        var detector = SilenceDetector(
            pauseThresholdSeconds: 0.4,
            speechFloor: 0.012,
            speechMultiplier: 2.6,
            speechMargin: 0.006
        )
        detector.skipCalibration(noiseFloor: 0.01)
        let t0 = Date()
        detector.markSpeech(now: t0)
        XCTAssertFalse(detector.update(rms: 0.01, now: t0.addingTimeInterval(0.25)))
        XCTAssertTrue(detector.isPaused(now: t0.addingTimeInterval(0.5)))
    }

    func testLoudAmbientCalibratesSoPauseStillWorks() {
        var detector = SilenceDetector(pauseThresholdSeconds: 0.45, speechFloor: 0.012)
        let t0 = Date()
        for i in 0..<8 {
            _ = detector.update(rms: 0.03, now: t0.addingTimeInterval(Double(i) * 0.08))
        }
        let tSpeak = t0.addingTimeInterval(0.7)
        XCTAssertFalse(detector.update(rms: 0.12, now: tSpeak))
        XCTAssertTrue(detector.hasHeardSpeech)
        XCTAssertTrue(detector.hadActivity)
        XCTAssertFalse(detector.update(rms: 0.03, now: tSpeak.addingTimeInterval(0.25)))
        XCTAssertTrue(detector.update(rms: 0.03, now: tSpeak.addingTimeInterval(0.55)))
    }

    func testActivityTrackedBelowSpeechGate() {
        var detector = SilenceDetector(pauseThresholdSeconds: 0.5, speechFloor: 0.05)
        detector.skipCalibration(noiseFloor: 0.01)
        // Above activity floor, below speech gate.
        _ = detector.update(rms: 0.02, now: Date())
        XCTAssertTrue(detector.hadActivity)
        XCTAssertFalse(detector.hasHeardSpeech)
    }
}
