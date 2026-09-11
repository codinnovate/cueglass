import CoreGraphics
import Foundation

/// Rectangle in display-local points, measured from the top-left corner.
struct ScreenRegion: Equatable, Sendable {
    let displayID: UInt32
    let rect: CGRect
}

enum ScreenRegionGeometry {
    static let minimumSize: CGFloat = 8

    /// AppKit screen coordinates are global and bottom-left based.
    static func selection(from start: CGPoint, to end: CGPoint, displayFrame: CGRect) -> CGRect? {
        let drag = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        ).intersection(displayFrame)
        guard !drag.isNull, drag.width >= minimumSize, drag.height >= minimumSize else { return nil }
        return CGRect(
            x: drag.minX - displayFrame.minX,
            y: displayFrame.maxY - drag.maxY,
            width: drag.width, height: drag.height
        )
    }

    /// Clip before pixel alignment so output never includes another display.
    static func captureRect(_ rect: CGRect, displaySize: CGSize, scale: CGFloat) throws -> CGRect {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height,
               displaySize.width, displaySize.height, scale].allSatisfy({ $0.isFinite }),
              scale > 0, rect.width > 0, rect.height > 0 else {
            throw ScreenCaptureError.invalidRegion
        }
        let clipped = rect.intersection(CGRect(origin: .zero, size: displaySize))
        guard !clipped.isNull, clipped.width >= minimumSize, clipped.height >= minimumSize else {
            throw ScreenCaptureError.invalidRegion
        }
        // Round inward: retain only pixels inside the selected rectangle.
        let x = ceil(clipped.minX * scale) / scale
        let y = ceil(clipped.minY * scale) / scale
        return CGRect(x: x, y: y,
                      width: floor(clipped.maxX * scale) / scale - x,
                      height: floor(clipped.maxY * scale) / scale - y)
    }
}
