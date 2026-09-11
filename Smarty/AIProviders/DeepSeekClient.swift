import Foundation

/// DeepSeek's OpenAI-compatible Chat Completions API (https://api.deepseek.com/chat/completions).
/// Note this is a *different* shape from OpenAI's own Responses API. DeepSeek has no vision
/// input today, so attached images are dropped with a note appended to the prompt instead.
actor DeepSeekClient: AIProviderClienting {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

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
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let text = delta["content"] as? String,
                          !text.isEmpty else { continue }
                    receivedAny = true
                    yieldedAny = true
                    continuation.yield(text)
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
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if streaming {
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        urlRequest.httpBody = body
        return urlRequest
    }

    private func makeBody(_ request: AIRequest, stream: Bool) throws -> Data {
        var userInput = request.input
        if !request.images.isEmpty {
            userInput += "\n\n[\(request.images.count) image attachment(s) omitted — DeepSeek's API does not support image input.]"
        }

        var payload: [String: Any] = [
            "model": request.model,
            "stream": stream,
            "messages": [
                ["role": "system", "content": request.instructions],
                ["role": "user", "content": userInput]
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
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw OpenAIError.decoding("Invalid JSON")
        }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { throw OpenAIError.emptyResponse }
        return trimmed
    }
}
