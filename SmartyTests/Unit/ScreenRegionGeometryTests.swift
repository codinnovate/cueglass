import XCTest
@testable import Smarty

final class ScreenRegionGeometryTests: XCTestCase {
    func testTopLeftConversionAndReverseDragOnNegativeOriginDisplay() {
        let display = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let start = CGPoint(x: -1400, y: 650)
        let end = CGPoint(x: -1100, y: 450)
        let expected = CGRect(x: 40, y: 50, width: 300, height: 200)
        XCTAssertEqual(ScreenRegionGeometry.selection(from: start, to: end, displayFrame: display), expected)
        XCTAssertEqual(ScreenRegionGeometry.selection(from: end, to: start, displayFrame: display), expected)
    }

    func testDragClipsToStartingDisplay() {
        let display = CGRect(x: 0, y: 900, width: 1440, height: 900)
        XCTAssertEqual(ScreenRegionGeometry.selection(
            from: CGPoint(x: 1400, y: 950), to: CGPoint(x: 1600, y: 800), displayFrame: display
        ), CGRect(x: 1400, y: 850, width: 40, height: 50))
    }

    func testTinyAndEmptySelectionsCancel() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        for end in [CGPoint.zero, CGPoint(x: 7, y: 50), CGPoint(x: 50, y: 7)] {
            XCTAssertNil(ScreenRegionGeometry.selection(from: .zero, to: end, displayFrame: display))
        }
    }

    func testPixelAlignmentAtStandardAndRetinaScale() throws {
        let rect = CGRect(x: 10.25, y: 20.25, width: 100.5, height: 50.5)
        let size = CGSize(width: 1440, height: 900)
        XCTAssertEqual(try ScreenRegionGeometry.captureRect(rect, displaySize: size, scale: 1),
                       CGRect(x: 11, y: 21, width: 99, height: 49))
        XCTAssertEqual(try ScreenRegionGeometry.captureRect(rect, displaySize: size, scale: 2),
                       CGRect(x: 10.5, y: 20.5, width: 100, height: 50))
    }

    func testCaptureClipsEdgesAndRejectsInvalidInput() throws {
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(try ScreenRegionGeometry.captureRect(
            CGRect(x: -10, y: 80, width: 140, height: 40), displaySize: size, scale: 2
        ), CGRect(x: 0, y: 80, width: 100, height: 20))
        for rect in [CGRect.zero, CGRect(x: 101, y: 0, width: 20, height: 20),
                     CGRect(x: 0, y: 0, width: 7, height: 10),
                     CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20)] {
            XCTAssertThrowsError(try ScreenRegionGeometry.captureRect(rect, displaySize: size, scale: 2))
        }
    }
}
