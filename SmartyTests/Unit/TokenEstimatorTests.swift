import XCTest
@testable import Smarty

final class TokenEstimatorTests: XCTestCase {
    func testEstimateMinimum() {
        XCTAssertEqual(TokenEstimator.estimateTokens(in: ""), 1)
        XCTAssertEqual(TokenEstimator.estimateTokens(in: "abcd"), 1)
        XCTAssertEqual(TokenEstimator.estimateTokens(in: "abcdefgh"), 2)
    }

    func testTruncateUnderBudget() {
        XCTAssertEqual(TokenEstimator.truncateToTokenBudget("hi", maxTokens: 10), "hi")
    }

    func testTruncateOverBudget() {
        let long = String(repeating: "a", count: 100)
        let truncated = TokenEstimator.truncateToTokenBudget(long, maxTokens: 5)
        XCTAssertTrue(truncated.hasSuffix("…"))
        XCTAssertLessThanOrEqual(truncated.count, 21)
    }
}
