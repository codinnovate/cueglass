import Foundation

enum AppStatus: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case streaming
    case paused
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .streaming: return "Streaming"
        case .paused: return "Paused"
        case .error(let message): return "Error: \(message)"
        }
    }

    var isActive: Bool {
        switch self {
        case .listening, .thinking, .streaming: return true
        default: return false
        }
    }
}
