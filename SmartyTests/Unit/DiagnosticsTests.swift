import AppKit
import XCTest
@testable import Smarty

final class DiagnosticsTests: XCTestCase {
    func testEveryWindowLevelSitsAboveOverlayAndBelowRegionPicker() {
        for option in DiagnosticsWindowLevel.allCases {
            XCTAssertGreaterThan(option.windowLevel.rawValue, OverlayWindowTier.overlay.rawValue, option.rawValue)
            XCTAssertLessThan(option.windowLevel.rawValue, OverlayWindowTier.regionPicker.rawValue, option.rawValue)
        }
    }

    func testKioskOverlayLevelClearsDisplayShieldButStaysBelowCursor() {
        XCTAssertGreaterThan(OverlayWindowTier.maximum.rawValue, Int(CGShieldingWindowLevel()))
        XCTAssertLessThan(OverlayWindowTier.maximum.rawValue, Int(CGWindowLevelForKey(.cursorWindow)))
        XCTAssertGreaterThan(OverlayWindowTier.regionPicker.rawValue, OverlayWindowTier.maximum.rawValue)
    }

    func testWindowLevelsAreStrictlyAscending() {
        let raw = DiagnosticsWindowLevel.allCases.map(\.windowLevel.rawValue)
        XCTAssertEqual(raw, raw.sorted())
        XCTAssertEqual(Set(raw).count, raw.count)
    }

    func testCPUPercentFromDeltas() {
        XCTAssertEqual(ProcessMetricsSampler.cpuPercent(cpuDelta: 0.5, wallDelta: 1), 50, accuracy: 0.001)
        XCTAssertEqual(ProcessMetricsSampler.cpuPercent(cpuDelta: 3, wallDelta: 1), 300, accuracy: 0.001)
        XCTAssertEqual(ProcessMetricsSampler.cpuPercent(cpuDelta: 1, wallDelta: 0), 0)
        XCTAssertEqual(ProcessMetricsSampler.cpuPercent(cpuDelta: -1, wallDelta: 1), 0)
    }

    func testSamplerReadsLiveProcess() {
        let launch = Date(timeIntervalSinceNow: -10)
        var sampler = ProcessMetricsSampler(launchDate: launch)
        let first = sampler.sample()
        XCTAssertEqual(first.cpuPercent, 0, "First sample has no delta to measure against")
        XCTAssertGreaterThan(first.memoryFootprintBytes, 0)
        XCTAssertGreaterThan(first.threadCount, 0)
        XCTAssertGreaterThanOrEqual(first.uptime, 10)

        let second = sampler.sample()
        XCTAssertGreaterThanOrEqual(second.cpuPercent, 0)
    }

    func testDurationFormatting() {
        XCTAssertEqual(DiagnosticsView.format(duration: 0), "00:00:00")
        XCTAssertEqual(DiagnosticsView.format(duration: 3_725.9), "01:02:05")
    }
}
