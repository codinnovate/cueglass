import Foundation

/// Dispatches answer-generation requests to the concrete client for `request.provider`.
/// This is what call sites depend on instead of talking to a single vendor directly.
actor AIClientRouter: AIProviderClienting {
    private let openAI: any AIProviderClienting
    private let anthropic: any AIProviderClienting

    init(
        openAI: any AIProviderClienting,
        anthropic: any AIProviderClienting = AnthropicClient()
    ) {
        self.openAI = openAI
        self.anthropic = anthropic
    }

    private func client(for provider: AIProvider) -> any AIProviderClienting {
        switch provider {
        case .openAI: return openAI
        case .anthropic: return anthropic
        case .gemini, .deepSeek:
            // Wired up in a later step; route to OpenAI's client meanwhile is wrong,
            // so fail loudly instead of silently answering with the wrong vendor.
            return UnsupportedProviderClient(provider: provider)
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

/// Placeholder for providers not yet wired into the router.
private actor UnsupportedProviderClient: AIProviderClienting {
    let provider: AIProvider

    init(provider: AIProvider) {
        self.provider = provider
    }

    func complete(apiKey: String, request: AIRequest) async throws -> String {
        throw OpenAIError.network("\(provider.displayName) is not supported yet.")
    }

    func streamResponse(apiKey: String, request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: OpenAIError.network("\(provider.displayName) is not supported yet."))
        }
    }
}
