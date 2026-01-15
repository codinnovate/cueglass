import Foundation

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: TimeInterval) async throws {
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
}
