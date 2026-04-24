import AppKit
import XCTest
@testable import Smarty

final class ImageAttachmentTests: XCTestCase {
    func testFitsSizeLimitHelper() {
        let small = Data(repeating: 0xAB, count: 1024)
        XCTAssertTrue(ImageAttachment.fitsSizeLimit(small))

        let tooBig = Data(repeating: 0xCD, count: ImageAttachment.maxBytes + 1)
        XCTAssertFalse(ImageAttachment.fitsSizeLimit(tooBig))
    }

    func testMakeCompressesOversizedImageUnderLimit() {
        // Solid bitmap large enough that uncompressed PNG would exceed 4MB without JPEG compression.
        let size = NSSize(width: 2400, height: 2400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let attachment = ImageAttachment.make(from: image)
        XCTAssertNotNil(attachment)
        XCTAssertLessThanOrEqual(attachment!.byteCount, ImageAttachment.maxBytes)
        XCTAssertEqual(attachment!.mimeType, .jpeg)
        XCTAssertTrue(attachment!.dataURL.hasPrefix("data:image/jpeg;base64,"))
    }

    func testMultimodalPayloadUsesInputImageDataURLs() throws {
        let tiny = ImageAttachment(
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            mimeType: .jpeg
        )
        let request = OpenAIRequest(
            model: "gpt-4o-mini",
            instructions: "i",
            input: "Describe this",
            temperature: 0.2,
            stream: false,
            images: [tiny]
        )
        let body = try OpenAIPayloadBuilder.makeBody(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "input_text")
        XCTAssertEqual(content[0]["text"] as? String, "Describe this")
        XCTAssertEqual(content[1]["type"] as? String, "input_image")
        let url = try XCTUnwrap(content[1]["image_url"] as? String)
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
    }

    func testTextOnlyPayloadKeepsStringInput() throws {
        let request = OpenAIRequest(
            model: "gpt-4o-mini",
            instructions: "i",
            input: "hello",
            temperature: 0.2,
            stream: false
        )
        let body = try OpenAIPayloadBuilder.makeBody(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["input"] as? String, "hello")
    }
}
