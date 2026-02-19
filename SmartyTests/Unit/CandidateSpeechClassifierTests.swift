import XCTest
@testable import Smarty

final class CandidateSpeechClassifierTests: XCTestCase {
    func testDetectsReadingOwnAnswer() {
        let answer = """
        I would start with a hash map for two sum. For each number I check if the complement \
        already exists, otherwise I store the value and index. That gives average O(n) time.
        """
        let spoken = """
        I would start with a hash map for two sum. For each number I check if the complement \
        already exists otherwise I store the value
        """
        XCTAssertTrue(
            CandidateSpeechClassifier.isReadingProvidedAnswer(
                transcript: spoken,
                answers: [answer]
            )
        )
    }

    func testDoesNotFlagDistinctInterviewerQuestion() {
        let answer = """
        I would start with a hash map for two sum and explain the complement lookup approach.
        """
        let question = "Can you walk me through how you would design a rate limiter?"
        XCTAssertFalse(
            CandidateSpeechClassifier.isReadingProvidedAnswer(
                transcript: question,
                answers: [answer]
            )
        )
    }

    func testIgnoresVeryShortTranscripts() {
        XCTAssertFalse(
            CandidateSpeechClassifier.isReadingProvidedAnswer(
                transcript: "hash map",
                answers: ["I would start with a hash map for two sum using complements."]
            )
        )
    }

    func testEmptyAnswersNeverMatch() {
        XCTAssertFalse(
            CandidateSpeechClassifier.isReadingProvidedAnswer(
                transcript: "I would start with a hash map for two sum using complements here",
                answers: []
            )
        )
    }
}
