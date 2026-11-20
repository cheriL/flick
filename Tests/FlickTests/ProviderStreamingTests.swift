import Foundation
import Testing
@testable import Flick

@Suite struct ProviderStreamingTests {

    // MARK: - partialTranslation

    @Test func partialReturnsNilBeforeTranslationTagArrives() {
        #expect(Provider.partialTranslation(from: "<think>reasoning") == nil)
        #expect(Provider.partialTranslation(from: "plain text no tags") == nil)
        #expect(Provider.partialTranslation(from: "<translation") == nil)
    }

    @Test func partialReturnsAccumulatingTextInsideOpenTag() {
        #expect(Provider.partialTranslation(from: "<translation>你好") == "你好")
        #expect(Provider.partialTranslation(from: "<translation lang=\"zh\">你好世") == "你好世")
    }

    @Test func partialSkipsThinkBlockBeforeTag() {
        #expect(Provider.partialTranslation(from: "<think>x</think><translation>你好") == "你好")
    }

    @Test func partialReturnsFinalTextWhenTagCloses() {
        let raw = "<translation>你好</translation><target-pronunciation>nǐ hǎo</target-pronunciation>"
        #expect(Provider.partialTranslation(from: raw) == "你好")
    }

    @Test func partialReturnsNilForEmptyClosedTag() {
        #expect(Provider.partialTranslation(from: "<translation></translation>") == nil)
    }

    @Test func partialToleratesNewlinesInTranslation() {
        #expect(Provider.partialTranslation(from: "<translation>第一行\n第二行") == "第一行\n第二行")
    }

    // MARK: - streamDelta

    @Test func streamDeltaExtractsContent() {
        let json = "{\"choices\":[{\"delta\":{\"content\":\"你\"}}]}"
        let data = Data(json.utf8)
        #expect(Provider.streamDelta(from: data) == "你")
    }

    @Test func streamDeltaRoleOnlyYieldsEmptyString() {
        let json = "{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"
        let data = Data(json.utf8)
        #expect(Provider.streamDelta(from: data) == "")
    }

    @Test func streamDeltaNilForNonDeltaPayload() {
        #expect(Provider.streamDelta(from: Data("[DONE]".utf8)) == nil)
        #expect(Provider.streamDelta(from: Data("not json".utf8)) == nil)
    }
}
