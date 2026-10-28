import XCTest
@testable import Smarty

final class ConversationHistoryTests: XCTestCase {
    private func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func testSanitizerDropsLeadingAssistantAndTrailingUser() {
        let cleaned = ConversationHistorySanitizer.sanitize([
            ConversationMessage(role: .assistant, content: "stray"),
            ConversationMessage(role: .user, content: "q1"),
            ConversationMessage(role: .assistant, content: "a1"),
            ConversationMessage(role: .user, content: "unanswered")
        ])
        XCTAssertEqual(cleaned.map(\.content), ["q1", "a1"])
    }

    func testSanitizerMergesConsecutiveSameRoleAndDropsBlanks() {
        let cleaned = ConversationHistorySanitizer.sanitize([
            ConversationMessage(role: .user, content: "q1"),
            ConversationMessage(role: .user, content: "   "),
            ConversationMessage(role: .user, content: "q1 restated"),
            ConversationMessage(role: .assistant, content: "a1")
        ])
        XCTAssertEqual(cleaned.count, 2)
        XCTAssertEqual(cleaned[0].content, "q1\n\nq1 restated")
        XCTAssertEqual(cleaned[1].role, .assistant)
    }

    func testOpenAIBodySendsHistoryAsMessagesWithQuestionLast() throws {
        let body = try OpenAIPayloadBuilder.makeBody(
            OpenAIRequest(
                provider: .openAI,
                model: "gpt-4o-mini",
                instructions: "i",
                input: "now in Java",
                temperature: 0.3,
                stream: false,
                history: [
                    ConversationMessage(role: .user, content: "reverse a list"),
                    ConversationMessage(role: .assistant, content: "here is python")
                ]
            )
        )
        let items = decode(body)["input"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 3)
        XCTAssertEqual(items?.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual(items?.last?["content"] as? String, "now in Java")
    }

    func testOpenAIBodyKeepsPlainStringInputWhenNoHistory() throws {
        let body = try OpenAIPayloadBuilder.makeBody(
            OpenAIRequest(
                provider: .openAI, model: "gpt-4o-mini", instructions: "i",
                input: "q", temperature: 0.3, stream: false
            )
        )
        XCTAssertEqual(decode(body)["input"] as? String, "q")
    }
}
