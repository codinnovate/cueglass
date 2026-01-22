import Foundation
import Vision
import CoreGraphics

enum OCRAccuracy: Sendable {
    case fast
    case accurate
}

protocol OCRProcessing: Actor {
    func recognizeText(in image: CGImage, accuracy: OCRAccuracy) async throws -> String?
    func reset() async
}

extension OCRProcessing {
    func recognizeText(in image: CGImage) async throws -> String? {
        try await recognizeText(in: image, accuracy: .fast)
    }
}

actor OCRService: OCRProcessing {
    private var lastFrameHash: UInt64?
    private var lastTextNormalized: String?

    func recognizeText(in image: CGImage, accuracy: OCRAccuracy = .fast) async throws -> String? {
        let workingImage = downscaleIfNeeded(image, maxDimension: accuracy == .accurate ? 1800 : 1280)
        let hash = workingImage.averageLumaSample
        if let lastFrameHash, lastFrameHash == hash {
            return nil
        }
        lastFrameHash = hash

        let text = try await performOCR(on: workingImage, accuracy: accuracy)
        let normalized = text.normalizedForComparison()
        guard !normalized.isBlank else { return nil }

        if let lastTextNormalized, lastTextNormalized == normalized {
            return nil
        }
        lastTextNormalized = normalized
        return text.trimmed
    }

    func reset() {
        lastFrameHash = nil
        lastTextNormalized = nil
    }

    private func downscaleIfNeeded(_ image: CGImage, maxDimension: Int) -> CGImage {
        let maxSide = max(image.width, image.height)
        guard maxSide > maxDimension else { return image }
        let scale = CGFloat(maxDimension) / CGFloat(maxSide)
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private func performOCR(on image: CGImage, accuracy: OCRAccuracy) async throws -> String {
        // Vision completion can run off the actor — build the request in a nonisolated helper.
        try await Self.runVisionOCR(image: image, accuracy: accuracy)
    }

    private nonisolated static func runVisionOCR(image: CGImage, accuracy: OCRAccuracy) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let box = OnceResumeBox(continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    box.resume(.failure(error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                box.resume(.success(lines.joined(separator: "\n")))
            }
            request.recognitionLevel = accuracy == .accurate ? .accurate : .fast
            request.usesLanguageCorrection = accuracy == .accurate

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                box.resume(.failure(error))
            }
        }
    }
}

/// Ensures a throwing continuation resumes at most once from any queue.
private final class OnceResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<String, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }
}
