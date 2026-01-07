import Foundation

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct ConversationMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// One completed Q&A block shown in the overlay answer stack.
struct AnswerTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let question: String
    /// Spoken technical answer (show first — optimized for speed).
    var technicalAnswer: String
    /// Plain-language explanation under the technical answer.
    var friendlyAnswer: String
    let createdAt: Date

    /// Primary answer used for copy / regenerate / reading detection (technical).
    var answer: String { technicalAnswer }

    var isFriendlyPending: Bool {
        !technicalAnswer.isEmpty && friendlyAnswer.isEmpty
    }

    init(
        id: UUID = UUID(),
        index: Int,
        question: String,
        answer: String,
        friendlyAnswer: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.question = question
        self.technicalAnswer = answer
        self.friendlyAnswer = friendlyAnswer
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        index: Int,
        question: String,
        technicalAnswer: String,
        friendlyAnswer: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.question = question
        self.technicalAnswer = technicalAnswer
        self.friendlyAnswer = friendlyAnswer
        self.createdAt = createdAt
    }

    var combinedForCopy: String {
        var parts: [String] = []
        if !technicalAnswer.isEmpty {
            parts.append("Technical (spoken)\n\(technicalAnswer)")
        }
        if !friendlyAnswer.isEmpty {
            parts.append("Simple\n\(friendlyAnswer)")
        }
        return parts.joined(separator: "\n\n")
    }
}

struct TranscriptChunk: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let isFinal: Bool
    let createdAt: Date

    init(id: UUID = UUID(), text: String, isFinal: Bool, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.createdAt = createdAt
    }
}

struct OCRSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

struct DisplayInfo: Identifiable, Hashable, Sendable {
    let id: UInt32
    let name: String
    let width: Int
    let height: Int
}

struct MicrophoneInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}
