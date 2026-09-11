import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults
    private let keychain: KeychainServing
    private let settingsKey = "smarty.settings"
    private let historyKey = "smarty.recentHistory"

    var settings: AppSettings {
        didSet { persistSettings() }
    }

    var recentHistory: [ConversationMessage] {
        didSet { persistHistory() }
    }

    /// Persisted API keys (Keychain), one per provider. Edit via `saveAPIKey(_:for:)` / Settings Save button.
    private(set) var apiKeys: [AIProvider: String] = [:]

    /// The key for the currently selected provider.
    var apiKey: String { apiKeys[settings.provider] ?? "" }

    var hasAPIKey: Bool { hasAPIKey(for: settings.provider) }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !(apiKeys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainServing = KeychainService()
    ) {
        self.defaults = defaults
        self.keychain = keychain

        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }

        if let data = defaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([ConversationMessage].self, from: data) {
            recentHistory = decoded
        } else {
            recentHistory = []
        }

        migrateOverlayFontSizeIfNeeded()
        reloadAPIKeysFromKeychain()
    }

    func reloadAPIKeysFromKeychain() {
        var loaded: [AIProvider: String] = [:]
        for provider in AIProvider.allCases {
            loaded[provider] = (try? keychain.loadAPIKey(for: provider)) ?? ""
        }
        apiKeys = loaded
    }

    @discardableResult
    func saveAPIKey(_ key: String, for provider: AIProvider) -> Result<Void, Error> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keychain.deleteAPIKey(for: provider)
                apiKeys[provider] = ""
            } else {
                try keychain.saveAPIKey(trimmed, for: provider)
                apiKeys[provider] = trimmed
            }
            // Re-read to confirm persistence.
            reloadAPIKeysFromKeychain()
            return .success(())
        } catch {
            AppLog.general.error("Failed to persist API key: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func resetPromptTemplate() {
        update { $0.promptTemplate = AppSettings.defaultPromptTemplate }
    }

    /// Upgrade older saved prompts that still discourage multi-variant coding answers,
    /// lack the mandatory inline technical-explanation Markdown format,
    /// or predate the role brief (they assumed every interview was a software one).
    func migratePromptTemplateIfNeeded() {
        let current = settings.promptTemplate
        let needsUpgrade = current.contains("Never dump large code blocks")
            || (!current.contains("multiple solution variations")
                && current.contains("For coding interviews:"))
            || !current.contains("INLINE TECHNICAL EXPLANATIONS")
            || !current.contains("Follow the role brief")
        guard needsUpgrade else { return }
        resetPromptTemplate()
    }

    /// Bump legacy default font (14) to the new readable default (17) once.
    private func migrateOverlayFontSizeIfNeeded() {
        let flagKey = "smarty.migratedOverlayFont17"
        guard !defaults.bool(forKey: flagKey) else { return }
        defaults.set(true, forKey: flagKey)
        if settings.overlayFontSize <= 14 {
            update { $0.overlayFontSize = 17 }
        }
    }

    func clearHistory() {
        recentHistory = []
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    private func persistHistory() {
        let capped = Array(recentHistory.suffix(50))
        guard let data = try? JSONEncoder().encode(capped) else { return }
        defaults.set(data, forKey: historyKey)
    }
}
