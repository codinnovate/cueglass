import XCTest
@testable import Smarty

final class ContextStoreTests: XCTestCase {
    func testOCRDedupe() async {
        let store = ContextStore()
        await store.appendOCR(OCRSnapshot(text: "Hello World"))
        await store.appendOCR(OCRSnapshot(text: " hello   world "))
        let snap = await store.snapshotForPrompt(maxTokens: 1000)
        XCTAssertEqual(snap.ocr.components(separatedBy: "---").count, 1)
    }

    func testClear() async {
        let store = ContextStore()
        await store.appendTranscript(TranscriptChunk(text: "q", isFinal: true))
        await store.appendAssistant("a")
        await store.replaceSummary("sum")
        await store.clear()
        let snap = await store.snapshotForPrompt(maxTokens: 1000)
        XCTAssertTrue(snap.transcript.isEmpty)
        XCTAssertTrue(snap.summary.isEmpty)
        XCTAssertTrue(snap.conversation.isEmpty)
    }

    func testNeedsSummarization() async {
        let store = ContextStore()
        let huge = String(repeating: "abcd", count: 2000)
        await store.appendTranscript(TranscriptChunk(text: huge, isFinal: true))
        let needs = await store.needsSummarization(maxTokens: 100)
        XCTAssertTrue(needs)
    }
}
