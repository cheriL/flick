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

    // MARK: - <think> stripping

    @Test func translateStripsThinkBlockBeforeTranslation() async throws {
        // Reasoning-model output: `<think>...</think>` prelude followed by the
        // actual translation. The user should see the translation only.
        let raw = """
        <think>The user wants me to translate the given English text into Chinese. I should only output the translation without any explanation or quotes.</think>
        高吞吐量部署：在低活动时段运行日志存储迁移。
        """
        MockURLProtocol.jsonResponder = { _ in
            (200, ["choices": [["message": ["content": raw]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        let result = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
        #expect(result == "高吞吐量部署：在低活动时段运行日志存储迁移。")
    }

    @Test func translateStripsMultilineThinkBlock() async throws {
        let raw = "<think>The user wants\nme to translate\nmulti-line reasoning.\n</think>\n你好世界"
        MockURLProtocol.jsonResponder = { _ in
            (200, ["choices": [["message": ["content": raw]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        let result = try await svc.translate("hello world", to: Locale.Language(identifier: "zh-Hans"))
        #expect(result == "你好世界")
    }

    @Test func translateLeavesContentWithoutThinkBlockUntouched() async throws {
        // Sanity check: no think block → no accidental mutation.
        MockURLProtocol.jsonResponder = { _ in
            (200, ["choices": [["message": ["content": "你好"]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        let result = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
        #expect(result == "你好")
    }

    @Test func translateStripsUnclosedThinkBlock() async throws {
        // Response truncated by max_tokens — `<think>` opener has no closing tag.
        // There's no reliable way to tell where reasoning ends and the answer
        // begins, so we treat everything from `<think>` to EOF as reasoning.
        // Users get an empty result instead of leaked reasoning noise.
        let raw = "<think>I need to translate this text.\n你好世界"
        MockURLProtocol.jsonResponder = { _ in
            (200, ["choices": [["message": ["content": raw]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        let result = try await svc.translate("hello world", to: Locale.Language(identifier: "zh-Hans"))
        #expect(result == "")
    }

    // MARK: - thinking suppression params

    @Test func requestBodyIncludesThinkingSuppressionByDefault() async throws {
        // disableThinking defaults to true → request body must carry both the
        // OpenAI-style and DeepSeek-style knobs so reasoning-capable models
        // skip their `<think>` prelude.
        var captured: [String: Any]?
        MockURLProtocol.jsonResponder = { request in
            captured = Self.jsonBody(of: request)
            return (200, ["choices": [["message": ["content": "你好"]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        let svc = OpenAICompatibleService(config: cfg, session: session)

        _ = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
        let body = try #require(captured)
        #expect(body["reasoning_effort"] as? String == "minimal")
        let thinking = try #require(body["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "disabled")
    }

    @Test func requestBodyOmitsThinkingSuppressionWhenDisabled() async throws {
        // When disableThinking is false, the body must NOT carry the
        // suppression fields — escape hatch for providers that reject unknown
        // params (e.g. some self-hosted gateways).
        var captured: [String: Any]?
        MockURLProtocol.jsonResponder = { request in
            captured = Self.jsonBody(of: request)
            return (200, ["choices": [["message": ["content": "你好"]]]])
        }
        let session = URLSession(configuration: .mock())
        var cfg = AIConfig.default
        cfg.apiKey = "sk-test"
        cfg.disableThinking = false
        let svc = OpenAICompatibleService(config: cfg, session: session)

        _ = try await svc.translate("hello", to: Locale.Language(identifier: "zh-Hans"))
        let body = try #require(captured)
        #expect(body["reasoning_effort"] == nil)
        #expect(body["thinking"] == nil)
    }

    /// URLSession often moves the body out of `httpBody` and into
    /// `httpBodyStream` before handing the request to URLProtocol, so reading
    /// `httpBody` directly returns nil. Drain the stream to recover the bytes.
    private static func jsonBody(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let bufSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufSize)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
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