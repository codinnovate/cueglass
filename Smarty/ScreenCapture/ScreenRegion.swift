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

    /// Convert a display-local point rectangle into an inward-rounded pixel crop for
    /// a captured full-display image. Deriving each axis from the actual image avoids
    /// ScreenCaptureKit sourceRect inconsistencies on Retina and mixed-scale displays.
    static func pixelCropRect(
        _ rect: CGRect,
        displaySize: CGSize,
        imageSize: CGSize
    ) throws -> CGRect {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height,
               displaySize.width, displaySize.height,
               imageSize.width, imageSize.height].allSatisfy({ $0.isFinite }),
              displaySize.width > 0, displaySize.height > 0,
              imageSize.width > 0, imageSize.height > 0,
              rect.width > 0, rect.height > 0 else {
            throw ScreenCaptureError.invalidRegion
        }
        let clipped = rect.intersection(CGRect(origin: .zero, size: displaySize))
        guard !clipped.isNull, clipped.width >= minimumSize, clipped.height >= minimumSize else {
            throw ScreenCaptureError.invalidRegion
        }
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height
        // Round inward: retain only pixels inside the selected rectangle.
        let x = ceil(clipped.minX * scaleX)
        let y = ceil(clipped.minY * scaleY)
        let maxX = floor(clipped.maxX * scaleX)
        let maxY = floor(clipped.maxY * scaleY)
        guard maxX > x, maxY > y else { throw ScreenCaptureError.invalidRegion }
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}
