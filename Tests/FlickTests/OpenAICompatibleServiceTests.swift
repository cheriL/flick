import Foundation
import Testing
@testable import Flick

@Suite(.serialized) final class OpenAICompatibleServiceTests {

    init() {
        // Reset static mock state so tests don't leak into each other.
        MockURLProtocol.jsonResponder = nil
        MockURLProtocol.lastRequest = nil
    }

    @Test func canHandleRejectsEmptyAndTooLong() {
        let svc = OpenAICompatibleService(config: .default)
        #expect(!svc.canHandle(""))
        #expect(!svc.canHandle(String(repeating: "x", count: 5001)))
        #expect(svc.canHandle("hello"))
    }

    @Test func translateOpenAISendsBearerAndParsesChoices() async throws {
        MockURLProtocol.jsonResponder = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            return (200, ["choices": [["message": ["content": "你好"]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        let result = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
        #expect(result == "你好")
    }

    @Test func translateMapsHTTP401ToTranslationError() async {
        MockURLProtocol.jsonResponder = { _ in (401, ["error": ["message": "bad key"]]) }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-bad"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        do {
            _ = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
            Issue.record("expected error")
        } catch let e as TranslationError {
            if case .http(let code, _) = e {
                #expect(code == 401)
            } else {
                Issue.record("wrong error: \(e)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func translateThrowsWhenAPIKeyMissing() async {
        var cfg = AIConfig.default
        cfg.apiKey = ""
        let svc = OpenAICompatibleService(config: cfg, session: .shared)
        do {
            _ = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
            Issue.record("expected error")
        } catch TranslationError.apiKeyMissing {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}

// MARK: - MockURLProtocol + URLSession factory

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var jsonResponder: ((URLRequest) -> (Int, [String: Any]))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = MockURLProtocol.jsonResponder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        MockURLProtocol.lastRequest = request
        let (status, body) = responder(request)
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLSessionConfiguration {
    static func mock() -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self] + (cfg.protocolClasses ?? [])
        return cfg
    }
}