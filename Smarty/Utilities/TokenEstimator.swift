import Foundation

enum TokenEstimator {
    /// Rough heuristic (~4 characters per token) for prompt budgeting.
    static func estimateTokens(in text: String) -> Int {
        max(1, text.count / 4)
    }

    static func truncateToTokenBudget(_ text: String, maxTokens: Int) -> String {
        let maxChars = max(0, maxTokens * 4)
        guard text.count > maxChars else { return text }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<end]) + "…"
    }
}
