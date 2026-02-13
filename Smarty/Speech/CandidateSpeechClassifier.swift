import Foundation

/// Detects when the candidate is reading Smarty's on-screen answer aloud
/// (vs the interviewer asking a new question).
enum CandidateSpeechClassifier {
    /// - Returns: true when `transcript` largely overlaps a provided answer.
    static func isReadingProvidedAnswer(
        transcript: String,
        answers: [String],
        minimumWords: Int = 5,
        coverageThreshold: Double = 0.42
    ) -> Bool {
        let spoken = significantWords(in: transcript)
        guard spoken.count >= minimumWords else { return false }

        for answer in answers {
            let answerWords = significantWords(in: answer)
            guard answerWords.count >= minimumWords else { continue }

            let spokenSet = Set(spoken)
            let answerSet = Set(answerWords)
            let overlap = spokenSet.intersection(answerSet).count
            let coverage = Double(overlap) / Double(spoken.count)
            if coverage >= coverageThreshold {
                return true
            }

            // Also catch near-verbatim prefixes of the answer.
            let prefix = Array(spoken.prefix(min(12, spoken.count)))
            let answerPrefix = Array(answerWords.prefix(min(16, answerWords.count)))
            let prefixOverlap = Set(prefix).intersection(Set(answerPrefix)).count
            if prefix.count >= 5, Double(prefixOverlap) / Double(prefix.count) >= 0.55 {
                return true
            }
        }
        return false
    }

    static func significantWords(in text: String) -> [String] {
        let normalized = text.normalizedForComparison()
        let parts = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let stop: Set<String> = [
            "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "for", "is", "are",
            "was", "were", "be", "been", "i", "you", "we", "they", "it", "that", "this",
            "with", "as", "at", "so", "if", "my", "me", "our", "your"
        ]
        return parts
            .map(String.init)
            .filter { $0.count > 1 && !stop.contains($0) }
    }
}
