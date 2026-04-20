import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// User-attached image for multimodal OpenAI requests (JPEG/PNG, capped ~4MB).
struct ImageAttachment: Identifiable, Equatable, Sendable {
    enum MimeType: String, Sendable, Equatable {
        case jpeg = "image/jpeg"
        case png = "image/png"

        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            }
        }

        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            }
        }
    }

    static let maxBytes = 4 * 1024 * 1024

    let id: UUID
    let data: Data
    let mimeType: MimeType

    init(id: UUID = UUID(), data: Data, mimeType: MimeType) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
    }

    var byteCount: Int { data.count }

    var dataURL: String {
        "data:\(mimeType.rawValue);base64,\(data.base64EncodedString())"
    }

    /// Downscaled preview suitable for thumbnail strips.
    @MainActor
    func thumbnail(maxPixel: CGFloat = 72) -> NSImage? {
        guard let source = NSImage(data: data) else { return nil }
        let size = source.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixel / max(size.width, size.height))
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        source.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        thumb.unlockFocus()
        return thumb
    }

    func makeCGImage() -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Factories

    /// Compresses / re-encodes so the payload stays under `maxBytes` when possible.
    static func make(from rawData: Data, preferredMIME: MimeType? = nil) -> ImageAttachment? {
        let detected = preferredMIME ?? detectMimeType(of: rawData) ?? .jpeg
        if rawData.count <= maxBytes, let mime = preferredMIME ?? detectMimeType(of: rawData) {
            return ImageAttachment(data: rawData, mimeType: mime)
        }

        guard let image = NSImage(data: rawData) else {
            guard rawData.count <= maxBytes else { return nil }
            return ImageAttachment(data: rawData, mimeType: detected)
        }
        return make(from: image, preferredMIME: detected)
    }

    static func make(from image: NSImage, preferredMIME: MimeType = .jpeg) -> ImageAttachment? {
        // Prefer JPEG for size; fall back to PNG if encoding fails.
        if preferredMIME == .png, let png = encodePNG(image), png.count <= maxBytes {
            return ImageAttachment(data: png, mimeType: .png)
        }

        var quality: CGFloat = 0.85
        while quality >= 0.35 {
            if let jpeg = encodeJPEG(image, quality: quality), jpeg.count <= maxBytes {
                return ImageAttachment(data: jpeg, mimeType: .jpeg)
            }
            quality -= 0.1
        }

        // Last resort: downscale then retry.
        if let scaled = downscaled(image, maxDimension: 1600),
           let jpeg = encodeJPEG(scaled, quality: 0.7),
           jpeg.count <= maxBytes {
            return ImageAttachment(data: jpeg, mimeType: .jpeg)
        }

        if let scaled = downscaled(image, maxDimension: 1024),
           let jpeg = encodeJPEG(scaled, quality: 0.55),
           jpeg.count <= maxBytes {
            return ImageAttachment(data: jpeg, mimeType: .jpeg)
        }

        return nil
    }

    static func make(fromFileURL url: URL) -> ImageAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let preferred: MimeType? = switch ext {
        case "png": .png
        case "jpg", "jpeg": .jpeg
        default: nil
        }
        return make(from: data, preferredMIME: preferred)
    }

    static func fromPasteboard(_ pasteboard: NSPasteboard = .general) -> ImageAttachment? {
        if let image = NSImage(pasteboard: pasteboard) {
            return make(from: image)
        }
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in types {
            if let data = pasteboard.data(forType: type) {
                return make(from: data, preferredMIME: type == .png ? .png : .jpeg)
            }
        }
        return nil
    }

    /// Returns true when `data` already fits the limit (used by unit tests).
    static func fitsSizeLimit(_ data: Data) -> Bool {
        data.count <= maxBytes
    }

    // MARK: - Encoding helpers

    private static func detectMimeType(of data: Data) -> MimeType? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        return nil
    }

    private static func encodeJPEG(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    private static func encodePNG(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    private static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: target)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}
