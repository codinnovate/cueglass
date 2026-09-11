import Foundation

/// Google's Gemini API (https://ai.google.dev), `generateContent` / `streamGenerateContent`.
actor GeminiClient: AIProviderClienting {
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    func complete(apiKey: String, request: AIRequest) async throws -> String {
        let body = try makeBody(request)
        guard let url = URL(string: "\(baseURL)/\(request.model):generateContent?key=\(apiKey)") else {
            throw OpenAIError.network("Invalid Gemini endpoint")
        }

        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            attempt += 1
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = body

                let (data, response) = try await session.data(for: urlRequest)
                try validate(response: response, data: data)
                return try parseCompletedText(from: data)
            } catch let error as OpenAIError {
                lastError = error
                if shouldRetry(error), attempt < 3 {
                    try await Task.sleep(seconds: Double(attempt) * 1.5)
                    continue
                }
                throw error
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(seconds: Double(attempt) * 1.5)
                    continue
                }
            }
        }
        throw lastError ?? OpenAIError.network("Unknown failure")
    }

    func streamResponse(apiKey: String, request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.performStream(apiKey: apiKey, request: request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performStream(
        apiKey: String,
        request: AIRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "\(baseURL)/\(request.model):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            throw OpenAIError.network("Invalid Gemini endpoint")
        }
        let body = try makeBody(request)

        var attempt = 0
        var lastError: Error?
        var yieldedAny = false

        while attempt < 3 {
            attempt += 1
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                urlRequest.httpBody = body

                let (bytes, response) = try await session.bytes(for: urlRequest)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 2000 { break }
                    }
                    throw mapHTTPError(status: http.statusCode, body: errorBody)
                }

                var receivedAny = false
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard let data = payload.data(using: .utf8) else { continue }
                    if let text = try? extractText(from: data), !text.isEmpty {
                        receivedAny = true
                        yieldedAny = true
                        continuation.yield(text)
                    }
                }

                if receivedAny { return }
                throw OpenAIError.emptyResponse
            } catch let error as OpenAIError {
                lastError = error
                if !yieldedAny, shouldRetry(error), attempt < 3 {
                    try await Task.sleep(seconds: Double(attempt) * 1.5)
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = OpenAIError.network(error.localizedDescription)
                if !yieldedAny, attempt < 3 {
                    try await Task.sleep(seconds: Double(attempt) * 1.5)
                    continue
                }
                throw lastError ?? OpenAIError.network(error.localizedDescription)
            }
        }
        throw lastError ?? OpenAIError.network("Unknown failure")
    }

    private func makeBody(_ request: AIRequest) throws -> Data {
        var parts: [[String: Any]] = [["text": request.input]]
        for image in request.images {
            let (mediaType, base64) = image.anthropicSourceComponents
            parts.append([
                "inline_data": [
                    "mime_type": mediaType,
                    "data": base64
                ]
            ])
        }

        var generationConfig: [String: Any] = [:]
        if request.provider.supportsTemperature(request.model) {
            generationConfig["temperature"] = request.temperature
        }

        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": request.instructions]]],
            "contents": [
                ["role": "user", "parts": parts]
            ],
            "generationConfig": generationConfig
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              !data.isEmpty else {
            throw OpenAIError.encodingFailed
        }
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("Invalid response")
        }
        if (200..<300).contains(http.statusCode) { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        throw mapHTTPError(status: http.statusCode, body: body)
    }

    private func mapHTTPError(status: Int, body: String) -> OpenAIError {
        if status == 401 || status == 403 { return .invalidAPIKey }
        if status == 429 { return .rateLimited }
        if status == 408 { return .timeout }
        return .server(status, body.isEmpty ? "Request failed" : body)
    }

    private func shouldRetry(_ error: OpenAIError) -> Bool {
        switch error {
        case .rateLimited, .timeout, .network:
            return true
        case .server(let code, _) where code >= 500:
            return true
        default:
            return false
        }
    }

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        return textFromCandidates(json)
    }

    private func parseCompletedText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.decoding("Invalid JSON")
        }
        let text = textFromCandidates(json).trimmed
        guard !text.isEmpty else { throw OpenAIError.emptyResponse }
        return text
    }

    private func textFromCandidates(_ json: [String: Any]) -> String {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return ""
        }
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}
