import Foundation

actor ContextStore {
    private(set) var transcriptChunks: [TranscriptChunk] = []
    private(set) var ocrSnapshots: [OCRSnapshot] = []
    private(set) var conversation: [ConversationMessage] = []
    private(set) var summary: String = ""
    private(set) var currentTopic: String = ""

    private let maxTranscript = 40
    private let maxOCR = 20
    private let maxConversation = 30

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
