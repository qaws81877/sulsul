import Foundation

/// Named deadlines for the default Korean cleanup pipeline.
/// OpenAI falls back to Anthropic when the first token is later than
/// `openAIFirstToken` or the full response is later than `openAIOverall`.
/// `anthropicOverall` is a safety cap so a stalled Anthropic stream cannot hang dictation.
enum KoreanCleanupTimeouts {
    static let openAIFirstToken: TimeInterval = 2.5
    static let openAIOverall: TimeInterval = 6
    static let anthropicOverall: TimeInterval = 30
}

/// Output and time budget for one cleanup call, scaled to transcript length.
/// Short transcripts keep the base values, so their request bytes and deadlines are unchanged.
/// Caps exist only so a stalled stream cannot hang dictation forever.
struct KoreanCleanupBudget: Equatable {
    static let tokensPerCharacter = 2
    static let maxTokensCap = 16_000
    static let firstTokenSecondsPerCharacter: TimeInterval = 0.002
    static let firstTokenCap: TimeInterval = 10
    /// ~4 characters a second of speech, so 10 minutes is about 2,500 characters.
    /// 0.05 s/char gives that recording 125 s on OpenAI. The old 0.02 rate left
    /// a 1,000-character cleanup only 20 s.
    static let openAISecondsPerCharacter: TimeInterval = 0.05
    /// 0.10 s/char gives 2,500 characters 250 s. The old 0.03 rate left
    /// 1,000 characters on the 30 s floor, which timed out on Sonnet.
    static let anthropicSecondsPerCharacter: TimeInterval = 0.10
    static let overallCap: TimeInterval = 300
    /// The fallback call gets at least this long, even when OpenAI used its whole budget.
    static let fallbackMinimum: TimeInterval = 45

    let maxTokens: Int
    let openAIFirstToken: TimeInterval
    let openAIOverall: TimeInterval
    let anthropicOverall: TimeInterval

    static let base = KoreanCleanupBudget(
        maxTokens: KoreanCleanupModels.maxTokens,
        openAIFirstToken: KoreanCleanupTimeouts.openAIFirstToken,
        openAIOverall: KoreanCleanupTimeouts.openAIOverall,
        anthropicOverall: KoreanCleanupTimeouts.anthropicOverall
    )

    /// Extra wait for models that think before answering. Nil effort adds nothing,
    /// which is the Haiku fallback (thinking stays off).
    static func reasoningAllowance(for effort: AnthropicEffort?) -> TimeInterval {
        switch effort {
        case nil:
            return 0
        case .low:
            return 30
        case .medium:
            return 60
        case .high:
            return 120
        case .xhigh, .max:
            return 180
        }
    }

    /// Effort that will actually be sent. Models that cannot disable thinking
    /// run at low when the mode has not picked a level.
    static func anthropicEffort(model: String, selected: AnthropicEffort?) -> AnthropicEffort? {
        guard AnthropicReasoningPolicy.supportsEffortSelection(model) else { return nil }
        return selected ?? .default
    }

    static func forTranscript(
        _ transcript: String,
        anthropicEffort: AnthropicEffort? = nil
    ) -> KoreanCleanupBudget {
        let characters = transcript.count
        let seconds = TimeInterval(characters)
        let reasoning = reasoningAllowance(for: anthropicEffort)
        let openAICap = overallCap - fallbackMinimum
        return KoreanCleanupBudget(
            maxTokens: min(maxTokensCap, max(KoreanCleanupModels.maxTokens, characters * tokensPerCharacter)),
            openAIFirstToken: clamp(
                seconds * firstTokenSecondsPerCharacter,
                floor: KoreanCleanupTimeouts.openAIFirstToken,
                cap: firstTokenCap
            ),
            openAIOverall: clamp(
                seconds * openAISecondsPerCharacter,
                floor: KoreanCleanupTimeouts.openAIOverall,
                cap: openAICap
            ),
            anthropicOverall: clamp(
                seconds * anthropicSecondsPerCharacter + reasoning,
                floor: KoreanCleanupTimeouts.anthropicOverall + reasoning,
                cap: overallCap
            )
        )
    }

    /// Time for the Anthropic attempt after OpenAI. At least `fallbackMinimum`,
    /// and the Anthropic budget when the overall cap still has room.
    /// Nil only when OpenAI already used the whole cap.
    func anthropicFallbackLimit(afterOpenAIElapsed elapsed: TimeInterval) -> TimeInterval? {
        fallbackLimit(preferred: anthropicOverall, afterElapsed: elapsed)
    }

    /// Time for the OpenAI attempt after Anthropic. Same floor and cap as the other direction.
    func openAIFallbackLimit(afterAnthropicElapsed elapsed: TimeInterval) -> TimeInterval? {
        fallbackLimit(preferred: openAIOverall, afterElapsed: elapsed)
    }

    private func fallbackLimit(preferred: TimeInterval, afterElapsed elapsed: TimeInterval) -> TimeInterval? {
        let room = KoreanCleanupBudget.overallCap - elapsed
        guard room > 0 else { return nil }
        let wanted = max(KoreanCleanupBudget.fallbackMinimum, preferred)
        return min(wanted, room)
    }

    func withOpenAIOverall(_ limit: TimeInterval) -> KoreanCleanupBudget {
        KoreanCleanupBudget(
            maxTokens: maxTokens,
            openAIFirstToken: min(openAIFirstToken, limit),
            openAIOverall: limit,
            anthropicOverall: anthropicOverall
        )
    }

    func withAnthropicOverall(_ limit: TimeInterval) -> KoreanCleanupBudget {
        KoreanCleanupBudget(
            maxTokens: maxTokens,
            openAIFirstToken: openAIFirstToken,
            openAIOverall: openAIOverall,
            anthropicOverall: limit
        )
    }

    private static func clamp(_ value: TimeInterval, floor: TimeInterval, cap: TimeInterval) -> TimeInterval {
        min(cap, max(floor, value))
    }
}

enum KoreanCleanupModels {
    static let openAI = "gpt-6-luna"
    static let anthropic = "claude-haiku-5-5"
    static let maxTokens = 600
    static let openAIReasoningEffort = "none"
    static let anthropicThinkingType = "disabled"
    static let anthropicOutputEffort = "low"
    static let anthropicVersion = "2023-06-01"
}

/// Organize's own pair. The verbatim Default cleanup keeps `KoreanCleanupModels`.
enum KoreanOrganizeModels {
    static let anthropic = "claude-sonnet-5-5"
    static let openAI = KoreanCleanupModels.openAI
}

struct KoreanCleanupModelChoice: Equatable {
    static let defaults = KoreanCleanupModelChoice(
        openAI: KoreanCleanupModels.openAI,
        anthropic: KoreanCleanupModels.anthropic
    )

    let openAI: String
    let anthropic: String
    /// Used only when `anthropic` is a model with a selectable reasoning level.
    var anthropicEffort: AnthropicEffort? = nil
}

enum KoreanCleanupRoute: Equatable {
    case openAIThenAnthropic
    case anthropicThenOpenAI
    case anthropicOnly
    case pasteTranscript
}

enum KoreanCleanupFallbackReason: Error, Equatable {
    case requestFailed
    case firstTokenTimeout
    case overallTimeout
    case outputTruncated
}

struct KoreanCleanupKeys: Equatable {
    var openAI: Bool
    var anthropic: Bool
}

struct KoreanCleanupCredentials: Equatable {
    var openAI: String?
    var anthropic: String?

    var keys: KoreanCleanupKeys {
        KoreanCleanupKeys(
            openAI: Self.isPresent(openAI),
            anthropic: Self.isPresent(anthropic)
        )
    }

    var openAIToken: String? {
        Self.trimmed(openAI)
    }

    var anthropicToken: String? {
        Self.trimmed(anthropic)
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isPresent(_ value: String?) -> Bool {
        trimmed(value) != nil
    }
}

enum KoreanCleanupPolicy {
    static func route(keys: KoreanCleanupKeys) -> KoreanCleanupRoute {
        route(keys: keys, selectedProvider: nil)
    }

    /// OpenAI is primary for the verbatim Default pair. An explicit Anthropic selection uses that
    /// provider directly. Organize's untouched pair is handled by the overload that knows the prompt.
    static func route(keys: KoreanCleanupKeys, selectedProvider: String?) -> KoreanCleanupRoute {
        standardRoute(keys: keys, selectedProvider: selectedProvider)
    }

    static func route(
        keys: KoreanCleanupKeys,
        selectedProvider: String?,
        selectedModel: String?,
        promptId: UUID?
    ) -> KoreanCleanupRoute {
        if promptId == PromptTemplates.organizePromptId,
            isOrganizeStockSelection(providerName: selectedProvider, modelName: selectedModel)
        {
            if keys.anthropic, keys.openAI {
                return .anthropicThenOpenAI
            }
            if keys.anthropic {
                return .anthropicOnly
            }
            if keys.openAI {
                return .openAIThenAnthropic
            }
            return .pasteTranscript
        }
        return standardRoute(keys: keys, selectedProvider: selectedProvider)
    }

    /// The provider/model pair the app itself installed for cleanup. A different model is a user choice.
    static func isOrganizeStockSelection(providerName: String?, modelName: String?) -> Bool {
        if isDefaultCleanupSelection(providerName: providerName, modelName: modelName) {
            return true
        }
        let provider = providerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let usesAnthropic = provider.isEmpty || provider == AIProvider.anthropic.rawValue
        let usesSonnet = model.isEmpty || model == KoreanOrganizeModels.anthropic
        return usesAnthropic && usesSonnet
    }

    private static func standardRoute(
        keys: KoreanCleanupKeys,
        selectedProvider: String?
    ) -> KoreanCleanupRoute {
        if selectedProvider == AIProvider.anthropic.rawValue {
            return keys.anthropic ? .anthropicOnly : .pasteTranscript
        }
        if keys.openAI {
            return .openAIThenAnthropic
        }
        if keys.anthropic {
            return .anthropicOnly
        }
        return .pasteTranscript
    }

    static func shouldFallBackToAnthropic(
        _ reason: KoreanCleanupFallbackReason,
        hasAnthropicKey: Bool
    ) -> Bool {
        switch reason {
        case .requestFailed, .firstTokenTimeout, .overallTimeout, .outputTruncated:
            return hasAnthropicKey
        }
    }

    /// Error surfaced when every cleanup provider failed, so the caller pastes the raw transcript
    /// with a warning instead of recording it as a successful enhancement.
    /// Timeouts are not mapped to `.timeout`: the pipeline already tried each provider, and a
    /// retry in `makeRequestWithRetry` would multiply the wait.
    static func enhancementError(for reason: KoreanCleanupFallbackReason) -> EnhancementError {
        switch reason {
        case .requestFailed:
            return .enhancementFailed
        case .outputTruncated:
            return .outputTruncated
        case .firstTokenTimeout, .overallTimeout:
            return .customError(EnhancementError.timeout.errorDescription ?? "")
        }
    }

    /// Built-in Korean prompts that run on the default cleanup pipeline.
    static let pipelinePromptIds: Set<UUID> = [
        PromptTemplates.defaultPromptId,
        PromptTemplates.organizePromptId,
    ]

    /// A built-in Korean prompt with OpenAI, Anthropic, or no provider runs on the cleanup pipeline,
    /// whichever model of those providers the mode selected.
    static func usesDefaultPipeline(_ configuration: EnhancementRuntimeConfiguration) -> Bool {
        usesDefaultPipeline(
            promptId: configuration.prompt?.id,
            providerName: configuration.mode?.selectedAIProvider ?? configuration.provider?.rawValue
        )
    }

    static func usesDefaultPipeline(promptId: UUID?, providerName: String?) -> Bool {
        guard let promptId, pipelinePromptIds.contains(promptId) else {
            return false
        }
        return isPipelineProvider(providerName)
    }

    static func isPipelineProvider(_ providerName: String?) -> Bool {
        guard let providerName, !providerName.isEmpty else {
            return true
        }
        return providerName == AIProvider.openAI.rawValue || providerName == AIProvider.anthropic.rawValue
    }

    /// The mode's model for the provider that is called first, or the default model when unset.
    static func models(
        selectedProvider: String?,
        selectedModel: String?,
        anthropicEffort: AnthropicEffort? = nil,
        promptId: UUID? = nil
    ) -> KoreanCleanupModelChoice {
        if promptId == PromptTemplates.organizePromptId,
            isOrganizeStockSelection(providerName: selectedProvider, modelName: selectedModel)
        {
            return KoreanCleanupModelChoice(
                openAI: KoreanOrganizeModels.openAI,
                anthropic: KoreanOrganizeModels.anthropic,
                anthropicEffort: anthropicEffort
            )
        }
        let model = selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch selectedProvider {
        case AIProvider.anthropic.rawValue:
            return KoreanCleanupModelChoice(
                openAI: KoreanCleanupModels.openAI,
                anthropic: model.isEmpty ? KoreanCleanupModels.anthropic : model,
                anthropicEffort: anthropicEffort
            )
        case AIProvider.openAI.rawValue:
            return KoreanCleanupModelChoice(
                openAI: model.isEmpty ? KoreanCleanupModels.openAI : model,
                anthropic: KoreanCleanupModels.anthropic
            )
        default:
            return .defaults
        }
    }

    /// The stock pair the app installs. Used to decide whether a mode is still untouched.

    static func isDefaultCleanupSelection(providerName: String?, modelName: String?) -> Bool {
        if let providerName, !providerName.isEmpty,
            providerName != AIProvider.openAI.rawValue,
            providerName != AIProvider.anthropic.rawValue
        {
            return false
        }

        if providerName == AIProvider.openAI.rawValue {
            if let modelName, !modelName.isEmpty, modelName != KoreanCleanupModels.openAI {
                return false
            }
        }

        if providerName == AIProvider.anthropic.rawValue {
            if let modelName, !modelName.isEmpty, modelName != KoreanCleanupModels.anthropic {
                return false
            }
        }

        return true
    }

    static func systemPrompt(from prompt: CustomPrompt) -> String {
        let trimmed = prompt.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            return prompt.promptText
        }
        return prompt.id == PromptTemplates.organizePromptId ? KoreanOrganizePrompt.text : KoreanCleanupPrompt.text
    }
}

/// Vocabulary appended after the frozen cleanup prompt. An empty list leaves the base bytes unchanged.
enum KoreanCleanupVocabulary {
    static func systemPrompt(base: String, vocabularyText: String) -> String {
        guard !vocabularyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }
        return base + "\n\n" + section(containing: vocabularyText)
    }

    static func section(containing vocabularyText: String) -> String {
        """
        # Custom Vocabulary
        Use these custom vocabulary words, proper nouns, acronyms, product names, and technical terms as the spelling authority. When the text clearly refers to one of these entries, replace similar-sounding or phonetically close transcription mistakes with the exact spelling shown below. Do not force a replacement when the text clearly means something else:
        Korean-script phonetic renderings or near-miss transcriptions of an entry (for example 클로드, 그록, 드록, 그록봇, 드록볶, 오픈에이아이) must be written in the entry's exact spelling. Do not force a replacement when the text clearly means a different ordinary Korean word.
        <CUSTOM_VOCABULARY>
        \(vocabularyText)
        </CUSTOM_VOCABULARY>
        """
    }
}

enum KoreanCleanupOpenAIDecision: Equatable {
    case accept
    case keepWaiting
    case fallBack(KoreanCleanupFallbackReason)
}

enum KoreanCleanupOpenAITiming {
    /// `firstTokenElapsed` and `completionElapsed` are measured from the start of the OpenAI call.
    /// A missing first token while the call is still running stays `.keepWaiting`; the caller
    /// applies `openAIFirstToken` when that deadline passes with no token.
    static func decision(
        failed: Bool,
        sawToken: Bool,
        firstTokenElapsed: TimeInterval?,
        completionElapsed: TimeInterval?,
        firstTokenLimit: TimeInterval = KoreanCleanupTimeouts.openAIFirstToken,
        overallLimit: TimeInterval = KoreanCleanupTimeouts.openAIOverall
    ) -> KoreanCleanupOpenAIDecision {
        if failed {
            return .fallBack(.requestFailed)
        }

        if let completionElapsed, completionElapsed > overallLimit {
            return .fallBack(.overallTimeout)
        }

        if sawToken {
            let elapsed = firstTokenElapsed ?? 0
            if elapsed > firstTokenLimit {
                return .fallBack(.firstTokenTimeout)
            }
        } else if completionElapsed != nil {
            return .fallBack(.requestFailed)
        } else {
            return .keepWaiting
        }

        if completionElapsed != nil {
            return .accept
        }

        return .keepWaiting
    }

    static func stalledReason(
        sawToken: Bool,
        elapsed: TimeInterval,
        firstTokenLimit: TimeInterval = KoreanCleanupTimeouts.openAIFirstToken,
        overallLimit: TimeInterval = KoreanCleanupTimeouts.openAIOverall
    ) -> KoreanCleanupFallbackReason {
        if elapsed > overallLimit {
            return .overallTimeout
        }
        if !sawToken, elapsed > firstTokenLimit {
            return .firstTokenTimeout
        }
        return .requestFailed
    }
}

enum KoreanCleanupRequestBuilder {
    struct ChatMessage: Encodable, Equatable {
        let role: String
        let content: String
    }

    struct OpenAIBody: Encodable, Equatable {
        let model: String
        let messages: [ChatMessage]
        let reasoningEffort: String
        let maxCompletionTokens: Int
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case reasoningEffort = "reasoning_effort"
            case maxCompletionTokens = "max_completion_tokens"
            case stream
        }
    }

    struct AnthropicBody: Encodable, Equatable {
        struct Thinking: Encodable, Equatable {
            let type: String
        }

        struct OutputConfig: Encodable, Equatable {
            let effort: String
        }

        let model: String
        let maxTokens: Int
        let system: String?
        let stream: Bool
        let thinking: Thinking
        let outputConfig: OutputConfig
        let messages: [ChatMessage]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case stream
            case thinking
            case outputConfig = "output_config"
            case messages
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(maxTokens, forKey: .maxTokens)
            try container.encodeIfPresent(system, forKey: .system)
            try container.encode(stream, forKey: .stream)
            try container.encode(thinking, forKey: .thinking)
            try container.encode(outputConfig, forKey: .outputConfig)
            try container.encode(messages, forKey: .messages)
        }
    }

    static func userMessage(transcript: String) -> String {
        "<TRANSCRIPT>\n\(transcript)\n</TRANSCRIPT>"
    }

    static func openAIBody(
        systemPrompt: String,
        transcript: String,
        maxTokens: Int = KoreanCleanupModels.maxTokens,
        model: String = KoreanCleanupModels.openAI
    ) -> OpenAIBody {
        OpenAIBody(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userMessage(transcript: transcript)),
            ],
            reasoningEffort: KoreanCleanupModels.openAIReasoningEffort,
            maxCompletionTokens: maxTokens,
            stream: true
        )
    }

    /// Shared Anthropic body. `temperature` is not a field, so it cannot be encoded.
    /// `thinking` and `output_config` come from `AnthropicReasoningPolicy`: thinking off at the lowest
    /// effort, except for models that cannot run without thinking, which think adaptively at `effort`
    /// (default low) and get room in `max_tokens` for it.
    static func anthropicMessagesBody(
        model: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        maxTokens: Int,
        stream: Bool,
        effort: AnthropicEffort? = nil
    ) -> AnthropicBody {
        let reasoning = AnthropicReasoningPolicy.settings(model: model, effort: effort)
        return AnthropicBody(
            model: model,
            maxTokens: maxTokens + reasoning.maxTokensHeadroom,
            system: systemPrompt,
            stream: stream,
            thinking: AnthropicBody.Thinking(type: reasoning.thinkingType),
            outputConfig: AnthropicBody.OutputConfig(effort: reasoning.effort),
            messages: messages
        )
    }

    static func anthropicBody(
        systemPrompt: String,
        transcript: String,
        maxTokens: Int = KoreanCleanupModels.maxTokens,
        model: String = KoreanCleanupModels.anthropic,
        effort: AnthropicEffort? = nil
    ) -> AnthropicBody {
        anthropicMessagesBody(
            model: model,
            systemPrompt: systemPrompt,
            messages: [
                ChatMessage(role: "user", content: userMessage(transcript: transcript))
            ],
            maxTokens: maxTokens,
            stream: true,
            effort: effort
        )
    }

    static func openAIJSON(
        systemPrompt: String,
        transcript: String,
        maxTokens: Int = KoreanCleanupModels.maxTokens,
        model: String = KoreanCleanupModels.openAI
    ) throws -> Data {
        try JSONEncoder().encode(
            openAIBody(systemPrompt: systemPrompt, transcript: transcript, maxTokens: maxTokens, model: model)
        )
    }

    static func anthropicJSON(
        systemPrompt: String,
        transcript: String,
        maxTokens: Int = KoreanCleanupModels.maxTokens,
        model: String = KoreanCleanupModels.anthropic,
        effort: AnthropicEffort? = nil
    ) throws -> Data {
        try JSONEncoder().encode(
            anthropicBody(
                systemPrompt: systemPrompt,
                transcript: transcript,
                maxTokens: maxTokens,
                model: model,
                effort: effort
            )
        )
    }
}

enum KoreanCleanupStreamEvent: Equatable {
    case ignore
    case done
    case content(String)
    /// The provider stopped at the output token limit, so the text is incomplete.
    case truncated
    case malformed
}

enum KoreanCleanupStreamParser {
    static func openAIEvent(fromLine line: String) -> KoreanCleanupStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(":") {
            return .ignore
        }
        guard trimmed.hasPrefix("data:") else {
            return .malformed
        }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .malformed
        }
        guard let choices = json["choices"] as? [[String: Any]] else {
            return .ignore
        }
        if (choices.first?["finish_reason"] as? String) == "length" {
            return .truncated
        }
        guard let delta = choices.first?["delta"] as? [String: Any] else {
            return .ignore
        }
        if let content = delta["content"] as? String {
            return .content(content)
        }
        return .ignore
    }

    static func anthropicEvent(fromLine line: String) -> KoreanCleanupStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(":") || trimmed.hasPrefix("event:") {
            return .ignore
        }
        guard trimmed.hasPrefix("data:") else {
            return .malformed
        }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .malformed
        }

        let type = json["type"] as? String
        if type == "error" {
            return .malformed
        }
        if type == "message_delta",
            let delta = json["delta"] as? [String: Any],
            (delta["stop_reason"] as? String) == "max_tokens"
        {
            return .truncated
        }
        guard type == "content_block_delta",
            let delta = json["delta"] as? [String: Any]
        else {
            return .ignore
        }
        if (delta["type"] as? String) == "text_delta", let text = delta["text"] as? String {
            return .content(text)
        }
        return .ignore
    }
}
