import XCTest

@testable import VoiceInk

final class ModelProviderPrivacyTests: XCTestCase {
    /// The mode form tells the user that audio is sent away for every provider that is not listed here.
    private let onDevice: Set<ModelProvider> = [.whisper, .fluidAudio, .transcribeCpp, .nativeApple]

    func testOnlyLocalEnginesRunOnDevice() {
        for provider in ModelProvider.allCases {
            XCTAssertEqual(
                provider.runsOnDevice,
                onDevice.contains(provider),
                "\(provider.rawValue) is classified the wrong way for the audio notice"
            )
        }
    }

    /// The AI Enhancement caption in the mode form uses the same rule as the runtime, so the notice
    /// that context is not sent can only show where the cleanup pipeline really runs.
    func testCleanupNoticeFollowsThePipelineRule() {
        let cleanup = PromptTemplates.defaultPromptId
        let organize = PromptTemplates.organizePromptId

        XCTAssertTrue(KoreanCleanupPolicy.usesDefaultPipeline(promptId: cleanup, providerName: nil))
        XCTAssertTrue(KoreanCleanupPolicy.usesDefaultPipeline(promptId: organize, providerName: "OpenAI"))
        XCTAssertTrue(KoreanCleanupPolicy.usesDefaultPipeline(promptId: organize, providerName: "Anthropic"))
        XCTAssertFalse(KoreanCleanupPolicy.usesDefaultPipeline(promptId: organize, providerName: "Gemini"))
        XCTAssertFalse(KoreanCleanupPolicy.usesDefaultPipeline(promptId: UUID(), providerName: "OpenAI"))
        XCTAssertFalse(KoreanCleanupPolicy.usesDefaultPipeline(promptId: nil, providerName: "OpenAI"))
    }

    func testCloudAndCustomProvidersAreRemote() {
        let remote: [ModelProvider] = [.groq, .elevenLabs, .deepgram, .mistral, .gemini, .openRouter, .custom]
        for provider in remote {
            XCTAssertFalse(provider.runsOnDevice, "\(provider.rawValue) sends audio to a remote service")
        }
    }
}
