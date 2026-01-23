import AppKit
import CoreGraphics

extension NSImage {
    convenience init?(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

extension CGImage {
    var averageLumaSample: UInt64 {
        // Downsample checksum for near-duplicate frame detection.
        let sampleW = min(32, width)
        let sampleH = min(32, height)
        guard sampleW > 0, sampleH > 0 else { return 0 }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: sampleW * sampleH)
        guard let context = CGContext(
            data: &pixels,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(self, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        var hash: UInt64 = 14695981039346656037
        for byte in pixels {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}
