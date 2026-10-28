import Foundation

actor ContextStore {
    private(set) var transcriptChunks: [TranscriptChunk] = []
    private(set) var ocrSnapshots: [OCRSnapshot] = []
    private(set) var conversation: [ConversationMessage] = []
    private(set) var summary: String = ""
    private(set) var currentTopic: String = ""

    private let maxTranscript = 40
    private let maxOCR = 20
    private let maxConversation = 40

    init(conversation: [ConversationMessage] = [], summary: String = "") {
        self.conversation = conversation
        self.summary = summary
        if conversation.count > maxConversation {
            self.conversation.removeFirst(conversation.count - maxConversation)
        }
    }

    func appendTranscript(_ chunk: TranscriptChunk) {
        transcriptChunks.append(chunk)
        if transcriptChunks.count > maxTranscript {
            transcriptChunks.removeFirst(transcriptChunks.count - maxTranscript)
        }
        updateTopicIfNeeded(from: chunk.text)
    }

    func appendOCR(_ snapshot: OCRSnapshot) {
        if let last = ocrSnapshots.last,
           last.text.normalizedForComparison() == snapshot.text.normalizedForComparison() {
            return
        }
        ocrSnapshots.append(snapshot)
        if ocrSnapshots.count > maxOCR {
            ocrSnapshots.removeFirst(ocrSnapshots.count - maxOCR)
        }
        updateTopicIfNeeded(from: snapshot.text)
    }

    func appendAssistant(_ text: String) {
        conversation.append(ConversationMessage(role: .assistant, content: text))
        trimConversation()
    }

    func appendUser(_ text: String) {
        conversation.append(ConversationMessage(role: .user, content: text))
        trimConversation()
    }

    func replaceSummary(_ text: String) {
        summary = text
    }

    func clear() {
        transcriptChunks = []
        ocrSnapshots = []
        conversation = []
        summary = ""
        currentTopic = ""
    }

    func recentTranscript(limit: Int = 12) -> String {
        transcriptChunks.suffix(limit).map(\.text).joined(separator: " ")
    }

    func recentOCR(limit: Int = 5) -> String {
        ocrSnapshots.suffix(limit).map(\.text).joined(separator: "\n---\n")
    }

    /// Prior turns for the live answer call — oldest first, each turn clipped and the whole run capped so
    /// the hot path stays small. The question being asked right now is appended by the client, not here.
    func promptHistory(turns: Int = 20, maxTokens: Int = 2800) -> [ConversationMessage] {
        var selected: [ConversationMessage] = []
        var used = 0
        for message in conversation.suffix(turns).reversed() {
            let clipped = TokenEstimator.truncateToTokenBudget(message.content, maxTokens: 480)
            let cost = TokenEstimator.estimateTokens(in: clipped)
            if used + cost > maxTokens { break }
            used += cost
            selected.append(
                ConversationMessage(role: message.role, content: clipped, createdAt: message.createdAt)
            )
        }
        return selected.reversed()
    }

    func snapshotForPrompt(maxTokens: Int) -> ContextSnapshot {
        ContextSnapshot(
            summary: summary,
            topic: currentTopic,
            transcript: recentTranscript(),
            ocr: recentOCR(),
            conversation: Array(conversation.suffix(12)),
            maxTokens: maxTokens
        )
    }

    func needsSummarization(maxTokens: Int) -> Bool {
        let snap = snapshotForPrompt(maxTokens: maxTokens)
        return TokenEstimator.estimateTokens(in: snap.combinedRaw) > maxTokens
    }

    private func trimConversation() {
        if conversation.count > maxConversation {
            conversation.removeFirst(conversation.count - maxConversation)
        }
    }

    private func updateTopicIfNeeded(from text: String) {
        let trimmed = text.trimmed
        guard trimmed.count > 20 else { return }
        if currentTopic.isBlank || trimmed.count > currentTopic.count {
            currentTopic = TokenEstimator.truncateToTokenBudget(trimmed, maxTokens: 40)
        }
    }
}

struct ContextSnapshot: Sendable {
    let summary: String
    let topic: String
    let transcript: String
    let ocr: String
    let conversation: [ConversationMessage]
    let maxTokens: Int

    var combinedRaw: String {
        [summary, topic, transcript, ocr, conversation.map(\.content).joined(separator: "\n")]
            .joined(separator: "\n")
    }
}
