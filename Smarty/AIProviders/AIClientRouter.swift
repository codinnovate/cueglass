import Foundation

/// Dispatches answer-generation requests to the concrete client for `request.provider`.
/// This is what call sites depend on instead of talking to a single vendor directly.
actor AIClientRouter: AIProviderClienting {
    private let openAI: any AIProviderClienting
    private let anthropic: any AIProviderClienting
    private let gemini: any AIProviderClienting
    private let deepSeek: any AIProviderClienting

    init(
        openAI: any AIProviderClienting,
        anthropic: any AIProviderClienting = AnthropicClient(),
        gemini: any AIProviderClienting = GeminiClient(),
        deepSeek: any AIProviderClienting = DeepSeekClient()
    ) {
        self.openAI = openAI
        self.anthropic = anthropic
        self.gemini = gemini
        self.deepSeek = deepSeek
    }

    private func client(for provider: AIProvider) -> any AIProviderClienting {
        switch provider {
        case .openAI: return openAI
        case .anthropic: return anthropic
        case .gemini: return gemini
        case .deepSeek: return deepSeek
        }
    }

    func complete(apiKey: String, request: AIRequest) async throws -> String {
        try await client(for: request.provider).complete(apiKey: apiKey, request: request)
    }

    func streamResponse(apiKey: String, request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let inner = await self.client(for: request.provider)
                    .streamResponse(apiKey: apiKey, request: request)
                do {
                    for try await chunk in inner {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
