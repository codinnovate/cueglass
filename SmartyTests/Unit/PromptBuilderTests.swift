import XCTest
@testable import Smarty

final class PromptBuilderTests: XCTestCase {
    let builder = PromptBuilder()

    func testEmptyTemplateUsesDefault() {
        let snapshot = ContextSnapshot(
            summary: "",
            topic: "",
            transcript: "Tell me about yourself",
            ocr: "",
            conversation: [],
            maxTokens: 2000
        )
        let prompt = builder.build(systemTemplate: "   ", snapshot: snapshot)
        XCTAssertTrue(prompt.instructions.contains("interview assistant"))
        XCTAssertTrue(prompt.input.contains("Tell me about yourself"))
    }

    func testMergesOCRAndTranscript() {
        let snapshot = ContextSnapshot(
            summary: "Prior summary",
            topic: "Algorithms",
            transcript: "How would you reverse a linked list?",
            ocr: "Write a function reverseList",
            conversation: [ConversationMessage(role: .assistant, content: "Earlier answer")],
            maxTokens: 4000
        )
        let prompt = builder.build(systemTemplate: "Be concise.", snapshot: snapshot)
        XCTAssertTrue(prompt.instructions.hasPrefix("Be concise."))
        XCTAssertTrue(prompt.input.contains("Prior summary"))
        XCTAssertTrue(prompt.input.contains("Algorithms"))
        XCTAssertTrue(prompt.input.contains("reverseList"))
        XCTAssertTrue(prompt.input.contains("linked list"))
        XCTAssertTrue(prompt.input.contains("Earlier answer"))
    }

    func testRespectsTokenBudget() {
        let huge = String(repeating: "word ", count: 5000)
        let snapshot = ContextSnapshot(
            summary: huge,
            topic: huge,
            transcript: huge,
            ocr: huge,
            conversation: [],
            maxTokens: 200
        )
        let prompt = builder.build(systemTemplate: "x", snapshot: snapshot)
        // Budget floors at 500 tokens (~2000 chars) even when maxTokens is tiny.
        XCTAssertLessThan(prompt.input.count, huge.count)
        XCTAssertTrue(prompt.input.contains("…") || prompt.input.count <= 2500)
    }

    func testPreferredLanguageInjectedWhenNotAuto() {
        let snapshot = ContextSnapshot(
            summary: "",
            topic: "",
            transcript: "Write two sum",
            ocr: "",
            conversation: [],
            maxTokens: 2000
        )
        let withSwift = builder.build(
            systemTemplate: "Base.",
            snapshot: snapshot,
            preferredLanguage: .swift,
            interviewFocus: .coding,
            answerLength: .concise
        )
        XCTAssertTrue(withSwift.instructions.contains("prefer Swift"))
        XCTAssertTrue(withSwift.instructions.contains("Session focus: coding"))
        XCTAssertTrue(withSwift.instructions.contains("Answer length: concise"))

        let auto = builder.build(
            systemTemplate: "Base.",
            snapshot: snapshot,
            preferredLanguage: .auto,
            interviewFocus: .mixed,
            answerLength: .standard
        )
        XCTAssertFalse(auto.instructions.contains("prefer "))
        XCTAssertTrue(auto.instructions.contains("Session focus: mixed"))
    }
}
