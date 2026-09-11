import Foundation

/// An LLM vendor Cueglass can generate answers with. Speech-to-text always uses
/// OpenAI's Whisper endpoints regardless of which provider is selected here.
enum AIProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAI
    case anthropic
    case gemini
    case deepSeek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        case .deepSeek: return "DeepSeek"
        }
    }

    /// Keychain account name. OpenAI's matches the pre-multi-provider value so
    /// existing users' stored key keeps working with no migration.
    var keychainAccount: String {
        switch self {
        case .openAI: return "openai_api_key"
        case .anthropic: return "anthropic_api_key"
        case .gemini: return "gemini_api_key"
        case .deepSeek: return "deepseek_api_key"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"]
        case .anthropic:
            return ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]
        case .gemini:
            return ["gemini-2.5-flash", "gemini-2.5-pro"]
        case .deepSeek:
            return ["deepseek-chat", "deepseek-reasoner"]
        }
    }

    /// True unless the model is one of OpenAI's reasoning models (o1/o3/o4), which reject `temperature`.
    func supportsTemperature(_ model: String) -> Bool {
        guard self == .openAI else { return true }
        return !model.hasPrefix("o1") && !model.hasPrefix("o3") && !model.hasPrefix("o4")
    }

    /// DeepSeek's chat API has no image input today; the other three accept multimodal content.
    var supportsVision: Bool {
        self != .deepSeek
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openAI: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .deepSeek: return "sk-..."
        }
    }
}
