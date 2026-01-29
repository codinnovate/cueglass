import Foundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

protocol ScreenCapturing: Actor {
    func availableDisplays() async throws -> [DisplayInfo]
    func start(displayID: UInt32?, interval: TimeInterval, onFrame: @escaping @Sendable (CGImage) async -> Void) async throws
    func stop() async
    func updateInterval(_ interval: TimeInterval) async
    func captureFrame(displayID: UInt32?) async throws -> CGImage
}

actor ScreenCaptureService: ScreenCapturing {
    private var captureTask: Task<Void, Never>?
    private var interval: TimeInterval = 1.0
    private var onFrame: (@Sendable (CGImage) async -> Void)?
    private var displayID: UInt32?
    private var cachedContent: SCShareableContent?
    private var contentCachedAt: Date = .distantPast
    private let contentCacheTTL: TimeInterval = 2.0

    func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await shareableContent(forceRefresh: true)
        return content.displays.map { display in
            DisplayInfo(
                id: display.displayID,
                name: "Display \(display.displayID)",
                width: display.width,
                height: display.height
            )
        }
    }

    func start(
        displayID: UInt32?,
        interval: TimeInterval,
        onFrame: @escaping @Sendable (CGImage) async -> Void
    ) async throws {
        await stop()
        self.interval = max(0.5, interval)
        self.displayID = displayID
        self.onFrame = onFrame

        _ = try await resolveDisplay(forceRefresh: true)

        captureTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    if let image = try await self.captureOnce(forceRefresh: false) {
                        await self.onFrame?(image)
                    }
                } catch {
                    AppLog.capture.error("Capture failed: \(error.localizedDescription)")
                }
                let delay = await self.interval
                try? await Task.sleep(seconds: delay)
            }
        }
    }

    func stop() async {
        captureTask?.cancel()
        captureTask = nil
        onFrame = nil
        cachedContent = nil
    }

    func updateInterval(_ interval: TimeInterval) async {
        self.interval = max(0.5, interval)
    }

    func captureFrame(displayID: UInt32?) async throws -> CGImage {
        self.displayID = displayID ?? self.displayID
        guard let image = try await captureOnce(forceRefresh: true) else {
            throw ScreenCaptureError.noDisplay
        }
        return image
    }

    private func shareableContent(forceRefresh: Bool) async throws -> SCShareableContent {
        if !forceRefresh,
           let cachedContent,
           Date().timeIntervalSince(contentCachedAt) < contentCacheTTL {
            return cachedContent
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        contentCachedAt = Date()
        return content
    }

    private func resolveDisplay(forceRefresh: Bool) async throws -> SCDisplay {
        let content = try await shareableContent(forceRefresh: forceRefresh)
        if let displayID,
           let match = content.displays.first(where: { $0.displayID == displayID }) {
            return match
        }
        guard let first = content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }
        return first
    }

    private func captureOnce(forceRefresh: Bool) async throws -> CGImage? {
        let content = try await shareableContent(forceRefresh: forceRefresh)
        let display = try await resolveDisplay(forceRefresh: false)

        let smartyWindows = content.applications
            .filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: smartyWindows, exceptingWindows: [])

        // Cap capture resolution for continuous OCR speed.
        let maxWidth = 1600
        let scale = min(1.0, CGFloat(maxWidth) / CGFloat(max(display.width, 1)))
        let config = SCStreamConfiguration()
        config.width = max(1, Int(CGFloat(display.width) * scale))
        config.height = max(1, Int(CGFloat(display.height) * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display available for screen capture."
        }
    }
}
