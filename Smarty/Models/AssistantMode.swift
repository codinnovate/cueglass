import Foundation

enum AssistantMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case whisper
    case stream

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisper: return "Whisper"
        case .stream: return "Stream"
        }
    }
}
