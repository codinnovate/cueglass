import AppKit
import XCTest
@testable import Smarty

@MainActor
final class OverlayLifecycleTests: XCTestCase {
    private var environment: AppEnvironment { .shared }
    private var overlays: [NSWindow] {
        NSApp.windows.filter { $0.identifier == OverlayPanelController.windowIdentifier }
    }
    private var visibleStandardWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    func testStartupPresentsOnlyOverlay() throws {
        XCTAssertEqual(overlays.count, 1)
        XCTAssertTrue(try XCTUnwrap(overlays.first).isVisible)
        XCTAssertTrue(visibleStandardWindows.isEmpty)
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    func testReopenReusesHiddenOverlayWithoutOpeningStandardWindow() throws {
        let original = try XCTUnwrap(overlays.first)
        environment.overlayManager.hide()
        XCTAssertFalse(original.isVisible)
        let delegate = AppDelegate()
        for _ in 0..<3 {
            XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        }
        XCTAssertTrue(original.isVisible)
        XCTAssertEqual(overlays.count, 1)
        XCTAssertTrue(overlays.first === original)
        XCTAssertTrue(visibleStandardWindows.isEmpty)
    }

    func testSettingsMenuOpensOnlyOnDemandAndReusesSettingsWindow() async throws {
        XCTAssertTrue(visibleStandardWindows.isEmpty)
        let controller = StatusItemController(environment: environment)
        let menu = NSMenu()
        menu.autoenablesItems = false
        controller.menuNeedsUpdate(menu)
        XCTAssertFalse(menu.items.contains { $0.title == "Show Window" })
        let settingsIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Settings…" })
        menu.performActionForItem(at: settingsIndex)
        let deadline = Date().addingTimeInterval(3)
        while visibleStandardWindows.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let settings = try XCTUnwrap(visibleStandardWindows.first, "Settings menu failed to open Settings")
        defer { settings.close() }
        XCTAssertEqual(visibleStandardWindows.count, 1)
        menu.performActionForItem(at: settingsIndex)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(visibleStandardWindows.count, 1)
        XCTAssertTrue(visibleStandardWindows.first === settings)
        XCTAssertEqual(overlays.count, 1)
    }
}
