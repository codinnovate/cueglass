import Foundation

actor Debouncer {
    private var task: Task<Void, Never>?

    func debounce(seconds: TimeInterval, action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
