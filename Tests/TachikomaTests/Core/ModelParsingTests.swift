import Testing
@testable import Tachikoma

struct ModelParsingTests {
    @Test
    func `parse GPT-5 mini alias`() {
        let parsed = LanguageModel.parse(from: "gpt-5-mini")
        #expect(parsed == .openai(.gpt5Mini))
    }

    @Test
    func `parse GPT-5.5 base model`() {
        let parsed = LanguageModel.parse(from: "gpt-5.5")
        #expect(parsed == .openai(.gpt55))
    }

    @Test
    func `parse GPT-5.4 base model`() {
        let parsed = LanguageModel.parse(from: "gpt-5.4")
        #expect(parsed == .openai(.gpt54))
    }

    @Test
    func `parse GPT-5.4 nano alias`() {
        let parsed = LanguageModel.parse(from: "gpt54-nano")
        #expect(parsed == .openai(.gpt54Nano))
    }

    @Test
    func `LanguageModel rejects retired OpenAI ids`() {
        for model in ["gpt-4o", "gpt-4.1", "gpt-5.1", "gpt-5.2", "gpt-5-thinking"] {
            #expect(LanguageModel.parse(from: model) == nil)
        }
    }

    @Test
    func `parse Claude Opus 4.7 model id`() {
        let parsed = LanguageModel.parse(from: "claude-opus-4-7")
        #expect(parsed == .anthropic(.opus47))
    }

    @Test
    func `parse Claude Sonnet 4.5 snapshot id`() {
        let parsed = LanguageModel.parse(from: "claude-sonnet-4-5-20250929")
        #expect(parsed == .anthropic(.sonnet45))
    }

    @Test
    func `parse shorthand Claude alias`() {
        let parsed = LanguageModel.parse(from: "claude")
        #expect(parsed == .anthropic(.opus47))
    }

    @Test
    func `parse Gemini 3.1 Pro model id`() {
        let parsed = LanguageModel.parse(from: "gemini-3.1-pro-preview")
        #expect(parsed == .google(.gemini31ProPreview))
    }

    @Test
    func `parse shorthand Gemini alias`() {
        let parsed = LanguageModel.parse(from: "gemini")
        #expect(parsed == .google(.gemini31ProPreview))
    }

    @Test
    func `ModelSelector rejects legacy OpenAI before Ollama fallback`() throws {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            for model in ["gpt-4o", "gpt-4.1", "gpt-3.5-turbo", "o4-mini", "o3-mini", "gpt-5.2"] {
                #expect(throws: ModelValidationError.self) {
                    _ = try ModelSelector.parseModel(model)
                }
            }
        }
    }

    @Test
    func `ModelSelector rejects Claude 3 before Ollama fallback`() throws {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            #expect(throws: ModelValidationError.self) {
                _ = try ModelSelector.parseModel("claude-3-sonnet")
            }
        }
    }
}
