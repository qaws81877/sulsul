import XCTest

@testable import VoiceInk

final class KoreanOrganizeTests: XCTestCase {
    func testOrganizeSeedIsThePinnedPrompt() throws {
        let seed = try XCTUnwrap(
            PromptTemplates.seedPrompts.first { $0.id == PromptTemplates.organizePromptId }
        )
        XCTAssertEqual(seed.promptText, KoreanOrganizePrompt.text)
        XCTAssertFalse(seed.useSystemInstructions)

        let fixture = try String(
            contentsOf: fixtureURL("prompt_ko_organize_v1", fileExtension: "txt"),
            encoding: .utf8
        )
        XCTAssertEqual(KoreanOrganizePrompt.text, fixture)
    }

    func testVerbatimCleanupPromptIsStillSeeded() throws {
        let seed = try XCTUnwrap(
            PromptTemplates.seedPrompts.first { $0.id == PromptTemplates.defaultPromptId }
        )
        XCTAssertEqual(seed.promptText, KoreanCleanupPrompt.text)
    }

    func testBothKoreanPromptsUseTheDefaultPipeline() {
        for promptId in [PromptTemplates.defaultPromptId, PromptTemplates.organizePromptId] {
            XCTAssertTrue(KoreanCleanupPolicy.usesDefaultPipeline(configuration(promptId: promptId)))
        }
        XCTAssertFalse(
            KoreanCleanupPolicy.usesDefaultPipeline(configuration(promptId: PromptTemplates.chatPromptId))
        )
    }

    func testEmptyOrganizePromptFallsBackToOrganizeText() {
        let prompt = CustomPrompt(
            id: PromptTemplates.organizePromptId,
            title: "Organize",
            promptText: "  ",
            useSystemInstructions: false
        )
        XCTAssertEqual(KoreanCleanupPolicy.systemPrompt(from: prompt), KoreanOrganizePrompt.text)
    }

    func testBudgetKeepsBaseValuesForShortTranscripts() {
        XCTAssertEqual(KoreanCleanupBudget.forTranscript("음 오늘 저녁에 어 시간 돼"), .base)
        XCTAssertEqual(KoreanCleanupBudget.base.maxTokens, 600)
        XCTAssertEqual(KoreanCleanupBudget.base.openAIFirstToken, KoreanCleanupTimeouts.openAIFirstToken)
        XCTAssertEqual(KoreanCleanupBudget.base.openAIOverall, KoreanCleanupTimeouts.openAIOverall)
        XCTAssertEqual(KoreanCleanupBudget.base.anthropicOverall, KoreanCleanupTimeouts.anthropicOverall)
    }

    func testBudgetScalesWithTranscriptLength() {
        let short = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 1_000))
        let long = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 4_000))
        XCTAssertEqual(short.maxTokens, 2_000)
        XCTAssertEqual(long.maxTokens, 8_000)
        // 1,000 characters used to sit on the 30 s Anthropic floor (1,000 × 0.03).
        XCTAssertEqual(short.openAIOverall, 50, accuracy: 0.001)
        XCTAssertEqual(short.anthropicOverall, 100, accuracy: 0.001)
        XCTAssertEqual(long.openAIOverall, 200, accuracy: 0.001)
        XCTAssertEqual(long.anthropicOverall, KoreanCleanupBudget.overallCap, accuracy: 0.001)
        XCTAssertEqual(long.openAIFirstToken, 8, accuracy: 0.001)
        XCTAssertGreaterThan(long.openAIOverall, short.openAIOverall)
        XCTAssertGreaterThan(long.anthropicOverall, short.anthropicOverall)
    }

    func testTenMinuteSpeechKeepsRoomForTheFallback() {
        let speech = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 2_500))
        XCTAssertEqual(speech.openAIOverall, 125, accuracy: 0.001)
        XCTAssertEqual(speech.anthropicOverall, 250, accuracy: 0.001)
        XCTAssertEqual(
            speech.anthropicFallbackLimit(afterOpenAIElapsed: speech.openAIOverall) ?? 0,
            175,
            accuracy: 0.001
        )
    }

    func testReasoningEffortAddsTimeAndHaikuDoesNot() {
        let plain = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 1_000))
        let low = KoreanCleanupBudget.forTranscript(
            String(repeating: "가", count: 1_000),
            anthropicEffort: .low
        )
        XCTAssertEqual(low.anthropicOverall, plain.anthropicOverall + 30, accuracy: 0.001)

        let shortLow = KoreanCleanupBudget.forTranscript("가", anthropicEffort: .low)
        XCTAssertEqual(
            shortLow.anthropicOverall,
            KoreanCleanupTimeouts.anthropicOverall + 30,
            accuracy: 0.001
        )

        let longHigh = KoreanCleanupBudget.forTranscript(
            String(repeating: "가", count: 2_500),
            anthropicEffort: .high
        )
        XCTAssertEqual(longHigh.anthropicOverall, KoreanCleanupBudget.overallCap, accuracy: 0.001)

        XCTAssertNil(
            KoreanCleanupBudget.anthropicEffort(model: KoreanCleanupModels.anthropic, selected: .high)
        )
        XCTAssertEqual(
            KoreanCleanupBudget.anthropicEffort(model: "claude-sonnet-5-5", selected: nil),
            .low
        )
        XCTAssertEqual(
            KoreanCleanupBudget.forTranscript(
                "가",
                anthropicEffort: KoreanCleanupBudget.anthropicEffort(
                    model: "claude-haiku-5-5",
                    selected: .max
                )
            ),
            .base
        )
    }

    func testBudgetCapsSoAStalledStreamStillEnds() {
        let huge = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 50_000))
        XCTAssertEqual(huge.maxTokens, KoreanCleanupBudget.maxTokensCap)
        XCTAssertEqual(huge.openAIFirstToken, KoreanCleanupBudget.firstTokenCap)
        XCTAssertEqual(
            huge.openAIOverall,
            KoreanCleanupBudget.overallCap - KoreanCleanupBudget.fallbackMinimum,
            accuracy: 0.001
        )
        XCTAssertEqual(huge.anthropicOverall, KoreanCleanupBudget.overallCap)
    }

    func testGenericEnhancementTimeoutScalesButNeverDropsBelowSetting() {
        XCTAssertEqual(EnhancementRequestSettings.timeout(forCharacters: 20, configured: 7), 7)
        XCTAssertEqual(EnhancementRequestSettings.timeout(forCharacters: 1_000, configured: 7), 30, accuracy: 0.001)
        XCTAssertEqual(EnhancementRequestSettings.timeout(forCharacters: 1_000, configured: 60), 60)
        XCTAssertEqual(
            EnhancementRequestSettings.timeout(forCharacters: 100_000, configured: 7),
            EnhancementRequestSettings.maximumScaledTimeout
        )
    }

    func testAnyOpenAIOrAnthropicModelUsesThePipeline() {
        let sonnet = configuration(
            promptId: PromptTemplates.organizePromptId,
            provider: AIProvider.anthropic.rawValue,
            model: "claude-sonnet-5"
        )
        XCTAssertTrue(KoreanCleanupPolicy.usesDefaultPipeline(sonnet))

        let sol = configuration(promptId: PromptTemplates.defaultPromptId, provider: "OpenAI", model: "gpt-6-sol")
        XCTAssertTrue(KoreanCleanupPolicy.usesDefaultPipeline(sol))

        let groq = configuration(promptId: PromptTemplates.organizePromptId, provider: "Groq", model: "llama")
        XCTAssertFalse(KoreanCleanupPolicy.usesDefaultPipeline(groq))
    }

    func testPipelineCallsTheModeModel() {
        XCTAssertEqual(
            KoreanCleanupPolicy.models(selectedProvider: "Anthropic", selectedModel: "claude-sonnet-5"),
            KoreanCleanupModelChoice(openAI: KoreanCleanupModels.openAI, anthropic: "claude-sonnet-5")
        )
        XCTAssertEqual(
            KoreanCleanupPolicy.models(selectedProvider: "OpenAI", selectedModel: "gpt-6-sol"),
            KoreanCleanupModelChoice(openAI: "gpt-6-sol", anthropic: KoreanCleanupModels.anthropic)
        )
        XCTAssertEqual(KoreanCleanupPolicy.models(selectedProvider: "OpenAI", selectedModel: " "), .defaults)
        XCTAssertEqual(KoreanCleanupPolicy.models(selectedProvider: nil, selectedModel: nil), .defaults)

        let body = KoreanCleanupRequestBuilder.anthropicBody(
            systemPrompt: "S",
            transcript: "T",
            model: "claude-sonnet-5"
        )
        XCTAssertEqual(body.model, "claude-sonnet-5")
        XCTAssertEqual(
            KoreanCleanupRequestBuilder.openAIBody(systemPrompt: "S", transcript: "T", model: "gpt-6-sol").model,
            "gpt-6-sol"
        )
    }

    func testRequestBodiesCarryTheBudgetTokens() throws {
        let openAI = try jsonObject(
            KoreanCleanupRequestBuilder.openAIJSON(systemPrompt: "S", transcript: "T", maxTokens: 1890)
        )
        XCTAssertEqual(openAI["max_completion_tokens"] as? Int, 1890)

        let anthropic = try jsonObject(
            KoreanCleanupRequestBuilder.anthropicJSON(systemPrompt: "S", transcript: "T", maxTokens: 1890)
        )
        XCTAssertEqual(anthropic["max_tokens"] as? Int, 1890)
    }

    func testEnsurePromptInsertsOrganizeAfterDefault() {
        let seeds = PromptTemplates.seedPrompts.filter { $0.id != PromptTemplates.organizePromptId }
        let updated = KoreanOrganizeAdoption.ensurePrompt(in: seeds)
        XCTAssertEqual(updated.count, seeds.count + 1)
        XCTAssertEqual(updated[0].id, PromptTemplates.defaultPromptId)
        XCTAssertEqual(updated[1].id, PromptTemplates.organizePromptId)

        XCTAssertEqual(KoreanOrganizeAdoption.ensurePrompt(in: updated), updated)
        XCTAssertTrue(KoreanOrganizeAdoption.ensurePrompt(in: []).isEmpty)
    }

    func testOnlyTheDefaultDictationModeSwitchesToOrganize() {
        XCTAssertTrue(KoreanOrganizeAdoption.shouldSwitchToOrganize(dictation()))
        XCTAssertTrue(
            KoreanOrganizeAdoption.shouldSwitchToOrganize(
                dictation(provider: AIProvider.anthropic.rawValue, model: KoreanCleanupModels.anthropic)
            )
        )
        XCTAssertFalse(
            KoreanOrganizeAdoption.shouldSwitchToOrganize(
                dictation(prompt: PromptTemplates.chatPromptId.uuidString)
            )
        )
        XCTAssertFalse(
            KoreanOrganizeAdoption.shouldSwitchToOrganize(dictation(provider: "Groq", model: "llama"))
        )
        XCTAssertFalse(
            KoreanOrganizeAdoption.shouldSwitchToOrganize(dictation(model: "gpt-6-astra"))
        )

        var other = dictation()
        other.id = UUID()
        XCTAssertFalse(KoreanOrganizeAdoption.shouldSwitchToOrganize(other))
    }

    func testDictationStarterUsesOrganize() throws {
        let template = try XCTUnwrap(StarterModeCatalog.templates.first { $0.kind == .clean })
        XCTAssertEqual(template.promptId, PromptTemplates.organizePromptId)
    }

    func testOrganizePromptStatesTheRegisterAndLengthRules() {
        let prompt = KoreanOrganizePrompt.text
        XCTAssertTrue(prompt.contains("확인해 주세요라고 하자"))
        XCTAssertTrue(prompt.contains("상태입니다"))
        XCTAssertTrue(prompt.contains("### 주제"))
        XCTAssertTrue(prompt.contains("오늘 저녁에 시간 돼?"))
        XCTAssertTrue(prompt.contains("700자 미만이면"))
        XCTAssertTrue(prompt.contains("템플릿만 만들어"))
        XCTAssertTrue(prompt.contains("슬랙"))
        XCTAssertFalse(prompt.contains("마크다운은 쓰지 마라"))
        XCTAssertFalse(prompt.contains("더 많이 쓴 쪽으로"))
    }

    func testOrganizeFixturesParseWithoutCallingProviders() throws {
        let lines = try String(
            contentsOf: fixtureURL("ko_organize_cases", fileExtension: "jsonl"),
            encoding: .utf8
        )
        .split(whereSeparator: \.isNewline)
        XCTAssertGreaterThanOrEqual(lines.count, 8)
        var byID: [String: [String: Any]] = [:]
        for line in lines {
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
            let id = try XCTUnwrap(object["id"] as? String)
            XCTAssertNotNil(object["input"] as? String)
            XCTAssertNotNil(object["expected"] as? String)
            XCTAssertNotNil(object["required"] as? [String])
            byID[id] = object
        }

        let jondaenmal = try XCTUnwrap(byID["o03"]?["expected"] as? String)
        XCTAssertTrue(jondaenmal.contains("않아서요"))
        XCTAssertFalse(jondaenmal.contains("말씀드리고 싶습니다"))

        let banmal = try XCTUnwrap(byID["o07"]?["expected"] as? String)
        XCTAssertTrue(banmal.contains("나에게"))
        XCTAssertFalse(banmal.contains("저에게"))
        XCTAssertFalse(banmal.contains("습니다"))

        let quoted = try XCTUnwrap(byID["o08"])
        let quotedInput = try XCTUnwrap(quoted["input"] as? String)
        let quotedExpected = try XCTUnwrap(quoted["expected"] as? String)
        XCTAssertTrue(quotedInput.contains("확인해 주세요"))
        XCTAssertTrue(quotedExpected.contains("확인해 주세요"))
        XCTAssertTrue(quotedExpected.contains("적어 둘게"))
        XCTAssertFalse(quotedExpected.contains("적겠습니다"))
    }

    private func dictation(
        prompt: String? = PromptTemplates.defaultPromptId.uuidString,
        provider: String? = AIProvider.openAI.rawValue,
        model: String? = KoreanCleanupModels.openAI
    ) -> ModeConfig {
        ModeConfig(
            id: KoreanCleanupAdoption.dictationModeID,
            name: "Dictation",
            isAIEnhancementEnabled: true,
            selectedPrompt: prompt,
            selectedAIProvider: provider,
            selectedAIModel: model
        )
    }

    private func configuration(
        promptId: UUID,
        provider: String? = AIProvider.openAI.rawValue,
        model: String? = KoreanCleanupModels.openAI
    ) -> EnhancementRuntimeConfiguration {
        EnhancementRuntimeConfiguration(
            mode: dictation(prompt: promptId.uuidString, provider: provider, model: model),
            isEnabled: true,
            prompt: CustomPrompt(id: promptId, title: "P", promptText: "x", useSystemInstructions: false),
            provider: .openAI,
            modelName: KoreanCleanupModels.openAI,
            useClipboardContext: false,
            useSelectedTextContext: false,
            useScreenCaptureContext: false
        )
    }

    private func fixtureURL(_ name: String, fileExtension: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: KoreanOrganizeTests.self).url(forResource: name, withExtension: fileExtension)
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
