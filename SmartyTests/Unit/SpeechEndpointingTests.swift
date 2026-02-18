import XCTest
@testable import Smarty

final class SpeechEndpointingTests: XCTestCase {
    func testWaitsUntilSpeechThenFlushesOnPause() {
        var ep = SpeechEndpointing(pauseThresholdSeconds: 0.4)
        ep.silence.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()

        XCTAssertEqual(
            ep.evaluate(rms: 0.001, bufferSeconds: 1.0, now: t0),
            .wait
        )
        XCTAssertEqual(
            ep.evaluate(rms: 0.06, bufferSeconds: 0.5, now: t0.addingTimeInterval(0.1)),
            .wait
        )
        XCTAssertEqual(
            ep.evaluate(rms: 0.0, bufferSeconds: 0.8, now: t0.addingTimeInterval(0.6)),
            .flush
        )
    }

    func testForceFlushAfterActivityWithoutCleanPause() {
        var ep = SpeechEndpointing(pauseThresholdSeconds: 2.0)
        ep.forceFlushSeconds = 1.0
        ep.minFlushGapSeconds = 0.2
        ep.silence.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()

        // Continuous “speech-like” energy never dips — still force flush by buffer age.
        XCTAssertEqual(
            ep.evaluate(rms: 0.08, bufferSeconds: 0.4, now: t0),
            .wait
        )
        XCTAssertEqual(
            ep.evaluate(rms: 0.08, bufferSeconds: 0.9, now: t0.addingTimeInterval(0.5)),
            .wait
        )
        XCTAssertEqual(
            ep.evaluate(rms: 0.08, bufferSeconds: 1.15, now: t0.addingTimeInterval(1.0)),
            .flush
        )
    }

    func testHardCapFlushesWithAnyActivity() {
        var ep = SpeechEndpointing(pauseThresholdSeconds: 5)
        ep.hardCapSeconds = 2.0
        ep.forceFlushSeconds = 10
        ep.silence.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        _ = ep.evaluate(rms: 0.02, bufferSeconds: 0.5, now: t0)
        XCTAssertTrue(ep.silence.hadActivity)
        XCTAssertEqual(
            ep.evaluate(rms: 0.01, bufferSeconds: 2.1, now: t0.addingTimeInterval(2.1)),
            .flush
        )
    }

    func testMutedAndTranscribingNeverFlush() {
        var ep = SpeechEndpointing(pauseThresholdSeconds: 0.3)
        ep.silence.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        _ = ep.evaluate(rms: 0.1, bufferSeconds: 1, now: t0)
        XCTAssertEqual(
            ep.evaluate(rms: 0, bufferSeconds: 1, now: t0.addingTimeInterval(1), isMuted: true),
            .wait
        )
        XCTAssertEqual(
            ep.evaluate(rms: 0, bufferSeconds: 1, now: t0.addingTimeInterval(1), isTranscribing: true),
            .wait
        )
    }

    func testShortBufferNeverFlushes() {
        var ep = SpeechEndpointing(pauseThresholdSeconds: 0.2)
        ep.minBufferSeconds = 0.5
        ep.silence.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        _ = ep.evaluate(rms: 0.1, bufferSeconds: 0.2, now: t0)
        XCTAssertEqual(
            ep.evaluate(rms: 0, bufferSeconds: 0.3, now: t0.addingTimeInterval(0.5)),
            .wait
        )
    }

    func testMinFlushGapPreventsDoubleFlush() {
        var ep = SpeechEndpointing(pauseThresholdSeconds: 0.3)
        ep.minFlushGapSeconds = 1.0
        ep.silence.skipCalibration(noiseFloor: 0.003)
        let t0 = Date()
        _ = ep.evaluate(rms: 0.1, bufferSeconds: 0.6, now: t0)
        XCTAssertEqual(
            ep.evaluate(rms: 0, bufferSeconds: 0.7, now: t0.addingTimeInterval(0.4)),
            .flush
        )
        ep.resetSilenceArm()
        _ = ep.evaluate(rms: 0.1, bufferSeconds: 0.6, now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(
            ep.evaluate(rms: 0, bufferSeconds: 0.7, now: t0.addingTimeInterval(0.9)),
            .wait,
            "Within min flush gap"
        )
    }
}
