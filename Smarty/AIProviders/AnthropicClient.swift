import Foundation

/// Anthropic's Messages API (https://api.anthropic.com/v1/messages).
actor AnthropicClient: AIProviderClienting {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let defaultMaxTokens = 4096

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
        let body = try makeBody(request, stream: false)

        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            attempt += 1
            do {
                let urlRequest = makeRequest(apiKey: apiKey, body: body)
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
        var attempt = 0
        var lastError: Error?
        var yieldedAny = false
        let body = try makeBody(request, stream: true)

        while attempt < 3 {
            attempt += 1
            do {
                let urlRequest = makeRequest(apiKey: apiKey, body: body, streaming: true)
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
                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else { continue }

                    if type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        receivedAny = true
                        yieldedAny = true
                        continuation.yield(text)
                    } else if type == "error",
                              let error = json["error"] as? [String: Any],
                              let message = error["message"] as? String {
                        throw mapHTTPError(status: 400, body: message)
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

    private func makeRequest(apiKey: String, body: Data, streaming: Bool = false) -> URLRequest {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if streaming {
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        urlRequest.httpBody = body
        return urlRequest
    }

    private func makeBody(_ request: AIRequest, stream: Bool) throws -> Data {
        var userContent: [[String: Any]] = [["type": "text", "text": request.input]]
        for image in request.images {
            let (mediaType, base64) = image.anthropicSourceComponents
            userContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ]
            ])
        }

        var payload: [String: Any] = [
            "model": request.model,
            "system": request.instructions,
            "max_tokens": defaultMaxTokens,
            "stream": stream,
            "messages": [
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]
        if request.provider.supportsTemperature(request.model) {
            payload["temperature"] = request.temperature
        }

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
        if status == 401 { return .invalidAPIKey }
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

    private func parseCompletedText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.decoding("Invalid JSON")
        }
        guard let content = json["content"] as? [[String: Any]] else {
            throw OpenAIError.emptyResponse
        }
        let chunks = content.compactMap { $0["text"] as? String }
        let joined = chunks.joined().trimmed
        guard !joined.isEmpty else { throw OpenAIError.emptyResponse }
        return joined
    }
}
