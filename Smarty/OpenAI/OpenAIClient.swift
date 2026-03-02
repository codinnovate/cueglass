import Foundation

enum OpenAIError: LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case timeout
    case network(String)
    case server(Int, String)
    case emptyResponse
    case decoding(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenAI API key in Settings."
        case .invalidAPIKey:
            return "The OpenAI API key is invalid."
        case .rateLimited:
            return "OpenAI rate limit reached. Retrying shortly…"
        case .timeout:
            return "The OpenAI request timed out."
        case .network(let message):
            return "Network error: \(message)"
        case .server(let code, let message):
            return "OpenAI error (\(code)): \(message)"
        case .emptyResponse:
            return "OpenAI returned an empty response."
        case .decoding(let message):
            return "Failed to parse OpenAI response: \(message)"
        case .encodingFailed:
            return "Failed to encode the OpenAI request."
        }
    }
}

struct OpenAIRequest: Sendable {
    let model: String
    let instructions: String
    let input: String
    let temperature: Double
    let stream: Bool
    let images: [ImageAttachment]

    init(
        model: String,
        instructions: String,
        input: String,
        temperature: Double,
        stream: Bool,
        images: [ImageAttachment] = []
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.temperature = temperature
        self.stream = stream
        self.images = images
    }
}

/// Builds Responses API JSON bodies (text-only or multimodal). Exposed for unit tests.
enum OpenAIPayloadBuilder {
    static func makeBody(_ request: OpenAIRequest) throws -> Data {
        var payload: [String: Any] = [
            "model": request.model,
            "instructions": request.instructions,
            "stream": request.stream,
            "store": false
        ]

        if request.images.isEmpty {
            payload["input"] = request.input
        } else {
            var content: [[String: Any]] = [
                ["type": "input_text", "text": request.input]
            ]
            for image in request.images {
                content.append([
                    "type": "input_image",
                    "image_url": image.dataURL
                ])
            }
            payload["input"] = [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        }

        if AppSettings.supportsTemperature(request.model) {
            payload["temperature"] = request.temperature
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              !data.isEmpty else {
            throw OpenAIError.encodingFailed
        }
        return data
    }
}

protocol OpenAIClienting: Actor {
    func streamResponse(apiKey: String, request: OpenAIRequest) -> AsyncThrowingStream<String, Error>
    func complete(apiKey: String, request: OpenAIRequest) async throws -> String
    func transcribeAudio(apiKey: String, wavData: Data, prompt: String?) async throws -> String
}

actor OpenAIClient: OpenAIClienting {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let transcriptionEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    /// Strong accuracy for accents + tech terms; falls back to whisper-1 if unavailable.
    private let preferredSTTModel = "gpt-4o-mini-transcribe"
    private let fallbackSTTModel = "whisper-1"

    init(session: URLSession = {
        let config = URLSessionConfiguration.default
        // Long streams (multi-variation coding answers) need generous timeouts.
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    func streamResponse(apiKey: String, request: OpenAIRequest) -> AsyncThrowingStream<String, Error> {
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

    func complete(apiKey: String, request: OpenAIRequest) async throws -> String {
        let body = try OpenAIPayloadBuilder.makeBody(OpenAIRequest(
            model: request.model,
            instructions: request.instructions,
            input: request.input,
            temperature: request.temperature,
            stream: false,
            images: request.images
        ))

        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            attempt += 1
            do {
                var urlRequest = URLRequest(url: endpoint)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    /// OpenAI Speech-to-Text (much stronger than Apple SFSpeech for accents / tech terms).
    func transcribeAudio(apiKey: String, wavData: Data, prompt: String?) async throws -> String {
        do {
            return try await performTranscription(
                apiKey: apiKey,
                wavData: wavData,
                prompt: prompt,
                model: preferredSTTModel
            )
        } catch let error as OpenAIError {
            if case .server(let code, _) = error, code == 404 || code == 400 {
                return try await performTranscription(
                    apiKey: apiKey,
                    wavData: wavData,
                    prompt: prompt,
                    model: fallbackSTTModel
                )
            }
            throw error
        }
    }

    private func performTranscription(
        apiKey: String,
        wavData: Data,
        prompt: String?,
        model: String
    ) async throws -> String {
        let boundary = "SmartyBoundary\(UUID().uuidString)"
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        appendField(name: "language", value: "en")
        appendField(name: "response_format", value: "json")
        if let prompt, !prompt.isEmpty {
            appendField(name: "prompt", value: prompt)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"utterance.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var urlRequest = URLRequest(url: transcriptionEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 60

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw OpenAIError.decoding("Missing transcription text")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAIError.emptyResponse }
        return trimmed
    }

    private func performStream(
        apiKey: String,
        request: OpenAIRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var attempt = 0
        var lastError: Error?
        var yieldedAny = false
        let body = try OpenAIPayloadBuilder.makeBody(request)

        while attempt < 3 {
            attempt += 1
            do {
                var urlRequest = URLRequest(url: endpoint)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                var dataBuffer = ""
                var sawCompleted = false

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    if line.isEmpty {
                        // SSE event boundary — payload already handled on each `data:` line.
                        dataBuffer = ""
                        continue
                    }

                    if line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            sawCompleted = true
                            break
                        }
                        dataBuffer = payload
                        if let delta = parseDelta(from: payload) {
                            receivedAny = true
                            yieldedAny = true
                            continuation.yield(delta)
                        } else if payloadContainsCompleted(payload) {
                            sawCompleted = true
                        } else if let errorMessage = parseStreamError(from: payload) {
                            throw mapHTTPError(status: 400, body: errorMessage)
                        }
                    }
                }

                // Prefer a clean completed stream; don't treat quiet completion as failure if we got deltas.
                if sawCompleted || receivedAny {
                    return
                }

                if !dataBuffer.isEmpty {
                    if let text = try? parseCompletedText(from: Data(dataBuffer.utf8)), !text.isBlank {
                        yieldedAny = true
                        continuation.yield(text)
                        return
                    }
                }

                throw OpenAIError.emptyResponse
            } catch let error as OpenAIError {
                lastError = error
                // Never retry after tokens were already yielded — that would duplicate into the UI mid-answer.
                if !yieldedAny, shouldRetry(error), attempt < 3 {
                    try await Task.sleep(seconds: Double(attempt) * 1.5)
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = OpenAIError.network(error.localizedDescription)
                // Mid-stream network blips must not restart the whole answer (duplicate tokens).
                if !yieldedAny, attempt < 3 {
                    try await Task.sleep(seconds: Double(attempt) * 1.5)
                    continue
                }
                throw lastError ?? OpenAIError.network(error.localizedDescription)
            }
        }
        throw lastError ?? OpenAIError.network("Unknown failure")
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

    private func parseDelta(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }

        switch type {
        case "response.output_text.delta":
            return json["delta"] as? String
        case "response.refusal.delta":
            return json["delta"] as? String
        case "response.output_text.done":
            // Final snapshot — only use if we somehow missed deltas.
            return nil
        default:
            return nil
        }
    }

    private func payloadContainsCompleted(_ payload: String) -> Bool {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return false }
        return type == "response.completed" || type == "response.output_text.done"
    }

    private func parseStreamError(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "error" else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return "Unknown streaming error"
    }

    private func parseCompletedText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.decoding("Invalid JSON")
        }

        if let outputText = json["output_text"] as? String, !outputText.isBlank {
            return outputText
        }

        if let output = json["output"] as? [[String: Any]] {
            var chunks: [String] = []
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content {
                    if let text = part["text"] as? String {
                        chunks.append(text)
                    } else if let text = part["value"] as? String {
                        chunks.append(text)
                    }
                }
            }
            let joined = chunks.joined().trimmed
            if !joined.isEmpty { return joined }
        }

        throw OpenAIError.emptyResponse
    }
}
