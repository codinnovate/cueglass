import AppKit
import XCTest
@testable import Smarty

@MainActor
final class RegionSelectionControllerTests: XCTestCase {
    private var controller: RegionSelectionController!

    override func setUp() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a connected macOS display") }
        controller = RegionSelectionController()
    }

    override func tearDown() async throws { controller?.cancel() }

    private var visiblePanels: [RegionSelectionPanel] {
        NSApp.windows.compactMap { $0 as? RegionSelectionPanel }.filter(\.isVisible)
    }

    func testEscapeClosesEveryPanelAndCompletesOnlyOnce() throws {
        var completions = 0
        controller.begin(blindMode: true) { result in
            XCTAssertNil(result)
            completions += 1
        }
        let panels = visiblePanels
        XCTAssertEqual(panels.count, NSScreen.screens.count)
        XCTAssertTrue(panels.allSatisfy { $0.sharingType == .none && !$0.styleMask.contains(.titled) })
        let panel = try XCTUnwrap(panels.first)
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        panel.keyDown(with: escape)
        controller.cancel()
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(controller.isSelecting)
        XCTAssertTrue(visiblePanels.isEmpty)
    }

    func testDisplayChangeCancelsAndDuplicateBeginDoesNotReplaceCompletion() {
        var completions = 0
        controller.begin(blindMode: false) { result in
            XCTAssertNil(result)
            completions += 1
        }
        controller.begin(blindMode: false) { _ in XCTFail("Duplicate selection replaced original") }
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(visiblePanels.isEmpty)
    }

    func testMouseReleaseReturnsRegionAfterClosingPanels() async throws {
        var selected: ScreenRegion?
        controller.begin(blindMode: true) { result in
            selected = result
            XCTAssertTrue(self.visiblePanels.isEmpty)
        }
        let panel = try XCTUnwrap(visiblePanels.first)
        let view = try XCTUnwrap(panel.contentView)
        panel.displayIfNeeded()
        // Ask the window server which window would receive the first click, without posting a click.
        try await Task.sleep(nanoseconds: 100_000_000)
        let hitPoint = panel.convertPoint(toScreen: CGPoint(x: 100, y: 100))
        XCTAssertEqual(NSWindow.windowNumber(at: hitPoint, belowWindowWithWindowNumber: 0), panel.windowNumber)
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: 1
            ))
        }
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 20, y: 30)))
        view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 220, y: 130)))
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 220, y: 130)))
        XCTAssertEqual(selected?.rect, CGRect(x: 20, y: panel.frame.height - 130, width: 200, height: 100))
        XCTAssertNotNil(selected?.displayID)
        XCTAssertFalse(controller.isSelecting)
    }
}
