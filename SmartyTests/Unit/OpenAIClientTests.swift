import XCTest
@testable import Smarty

final class OpenAIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testStreamYieldsDeltas() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = """
            data: {"type":"response.output_text.delta","delta":"Hi"}

            data: {"type":"response.output_text.delta","delta":"!"}

            data: [DONE]

            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let client = OpenAIClient(session: mockSession())
        var assembled = ""
        for try await delta in await client.streamResponse(
            apiKey: "sk-test",
            request: OpenAIRequest(model: "gpt-4o-mini", instructions: "i", input: "q", temperature: 0.7, stream: true)
        ) {
            assembled += delta
        }
        XCTAssertEqual(assembled, "Hi!")
    }

    func testInvalidAPIKey() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("unauthorized".utf8))
        }
        let client = OpenAIClient(session: mockSession())
        do {
            _ = try await client.complete(
                apiKey: "bad",
                request: OpenAIRequest(model: "gpt-4o-mini", instructions: "i", input: "q", temperature: 0.2, stream: false)
            )
            XCTFail("Expected error")
        } catch let error as OpenAIError {
            XCTAssertEqual(error, .invalidAPIKey)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testCompleteParsesOutputText() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"output_text":"Answer"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OpenAIClient(session: mockSession())
        let text = try await client.complete(
            apiKey: "sk",
            request: OpenAIRequest(model: "gpt-4o-mini", instructions: "i", input: "q", temperature: 0.2, stream: false)
        )
        XCTAssertEqual(text, "Answer")
    }

    func testSupportsTemperatureHelper() {
        XCTAssertTrue(AppSettings.supportsTemperature("gpt-4o-mini"))
        XCTAssertFalse(AppSettings.supportsTemperature("o4-mini"))
        XCTAssertFalse(AppSettings.supportsTemperature("o1-preview"))
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
