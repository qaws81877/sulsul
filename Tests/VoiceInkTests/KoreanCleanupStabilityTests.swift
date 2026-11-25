import XCTest

@testable import VoiceInk

final class KoreanCleanupStabilityTests: XCTestCase {
    func testCleanThrowsInsteadOfReturningTheTranscriptWhenNoProviderCanRun() async {
        do {
            _ = try await KoreanCleanupClient.clean(
                transcript: "음 그러니까 내일 회의는 세 시예요",
                systemPrompt: KoreanCleanupPrompt.text,
                credentials: KoreanCleanupCredentials(openAI: nil, anthropic: "  ")
            )
            XCTFail("clean must not report the raw transcript as a cleanup result")
        } catch let reason as KoreanCleanupFallbackReason {
            XCTAssertEqual(reason, .requestFailed)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFailedCleanupMapsToNonRetriedEnhancementErrors() {
        guard case .enhancementFailed = KoreanCleanupPolicy.enhancementError(for: .requestFailed) else {
            return XCTFail("requestFailed should map to enhancementFailed")
        }
        guard case .outputTruncated = KoreanCleanupPolicy.enhancementError(for: .outputTruncated) else {
            return XCTFail("outputTruncated should map to outputTruncated")
        }
        for reason in [KoreanCleanupFallbackReason.firstTokenTimeout, .overallTimeout] {
            guard case .customError(let message) = KoreanCleanupPolicy.enhancementError(for: reason) else {
                return XCTFail("\(reason) must not map to .timeout, which makeRequestWithRetry retries")
            }
            XCTAssertEqual(message, EnhancementError.timeout.errorDescription)
        }
    }

    func testStreamParsersReportOutputTruncation() {
        XCTAssertEqual(
            KoreanCleanupStreamParser.openAIEvent(
                fromLine: #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#
            ),
            .truncated
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.openAIEvent(
                fromLine: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
            ),
            .ignore
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.anthropicEvent(
                fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#
            ),
            .truncated
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.anthropicEvent(
                fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#
            ),
            .ignore
        )
        XCTAssertTrue(KoreanCleanupPolicy.shouldFallBackToAnthropic(.outputTruncated, hasAnthropicKey: true))
        XCTAssertFalse(KoreanCleanupPolicy.shouldFallBackToAnthropic(.outputTruncated, hasAnthropicKey: false))
    }

    func testAnthropicFallbackKeepsAMinimumInsideTheCap() {
        let budget = KoreanCleanupBudget.base
        XCTAssertEqual(
            budget.anthropicFallbackLimit(afterOpenAIElapsed: budget.openAIOverall),
            KoreanCleanupBudget.fallbackMinimum
        )
        XCTAssertNil(budget.anthropicFallbackLimit(afterOpenAIElapsed: KoreanCleanupBudget.overallCap))
        XCTAssertEqual(budget.withAnthropicOverall(4).anthropicOverall, 4)
        XCTAssertEqual(budget.withAnthropicOverall(4).maxTokens, budget.maxTokens)

        let capped = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 20_000))
        XCTAssertEqual(
            capped.openAIOverall,
            KoreanCleanupBudget.overallCap - KoreanCleanupBudget.fallbackMinimum,
            accuracy: 0.001
        )
        XCTAssertEqual(
            capped.anthropicFallbackLimit(afterOpenAIElapsed: capped.openAIOverall) ?? 0,
            KoreanCleanupBudget.fallbackMinimum,
            accuracy: 0.001
        )
        XCTAssertNil(capped.anthropicFallbackLimit(afterOpenAIElapsed: KoreanCleanupBudget.overallCap))
        XCTAssertNotNil(capped.anthropicFallbackLimit(afterOpenAIElapsed: 1))
    }

    func testAdoptionUsesAnExistingCleanupPrompt() {
        XCTAssertEqual(
            KoreanCleanupAdoption.cleanupPromptId(
                availablePromptIds: [PromptTemplates.defaultPromptId, PromptTemplates.organizePromptId]
            ),
            PromptTemplates.organizePromptId
        )
        XCTAssertEqual(
            KoreanCleanupAdoption.cleanupPromptId(availablePromptIds: [PromptTemplates.defaultPromptId]),
            PromptTemplates.defaultPromptId
        )
        XCTAssertNil(KoreanCleanupAdoption.cleanupPromptId(availablePromptIds: [PromptTemplates.chatPromptId]))
        XCTAssertNil(KoreanCleanupAdoption.cleanupPromptId(availablePromptIds: []))
    }
}
