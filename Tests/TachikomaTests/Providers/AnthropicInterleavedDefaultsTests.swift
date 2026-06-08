import Foundation
import Testing
@testable import Tachikoma

struct AnthropicInterleavedDefaultsTests {
    @Test
    func `Merged beta header includes required interleaved flags`() {
        let header = AnthropicProvider.mergedBetaHeader(existing: nil)
        #expect(header.contains("interleaved-thinking-2025-05-14"))
        #expect(header.contains("fine-grained-tool-streaming-2025-05-14"))

        let withExisting = AnthropicProvider.mergedBetaHeader(
            existing: "oauth-2025-04-20,interleaved-thinking-2025-05-14,oauth-2025-04-20",
        )
        let parts = withExisting
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        #expect(Set(parts).count == parts.count)
        #expect(parts.contains("oauth-2025-04-20"))
        #expect(parts.contains("interleaved-thinking-2025-05-14"))
        #expect(parts.contains("fine-grained-tool-streaming-2025-05-14"))
    }

    @Test
    func `Provider request includes beta header and thinking payload`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus45, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: true)
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-beta")?
            .contains("interleaved-thinking-2025-05-14") == true)
        #expect(
            urlRequest.value(forHTTPHeaderField: "anthropic-beta")?
                .contains("fine-grained-tool-streaming-2025-05-14") ==
                true,
        )

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-opus-4-5")
        #expect(json["stream"] as? Bool == true)

        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "enabled")
        #expect(thinking["budget_tokens"] as? Int == 12000)
    }

    @Test
    func `Opus 4_7 request strips unsupported sampling and uses adaptive thinking`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus47, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "claude-opus-4-7")
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
        #expect(json["top_k"] == nil)
        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "adaptive")
        #expect(thinking["budget_tokens"] == nil)
        let outputConfig = try #require(json["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "medium")
        #expect(json["max_tokens"] as? Int == 64)
    }

    @Test
    func `Opus 4_8 request strips unsupported sampling and uses adaptive thinking`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus48, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
            reasoningEffort: .low,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "claude-opus-4-8")
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
        #expect(json["top_k"] == nil)
        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "adaptive")
        #expect(thinking["budget_tokens"] == nil)
        let outputConfig = try #require(json["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "low")
        #expect(json["max_tokens"] as? Int == 64)
    }

    @Test
    func `Opus reasoning effort is kept when thinking is disabled`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus48, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            reasoningEffort: .low,
            providerOptions: .init(anthropic: .init(thinking: .disabled)),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let outputConfig = try #require(json["output_config"] as? [String: Any])

        #expect(json["thinking"] == nil)
        #expect(outputConfig["effort"] as? String == "low")
    }

    @Test
    func `Opus effort is sent without thinking when reasoning effort is configured`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus48, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            reasoningEffort: .low,
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let outputConfig = try #require(json["output_config"] as? [String: Any])

        #expect(json["thinking"] == nil)
        #expect(outputConfig["effort"] as? String == "low")
    }

    @Test
    func `Unsupported adaptive thinking is omitted for older Claude models`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus45, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            providerOptions: .init(anthropic: .init(thinking: .adaptive)),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["thinking"] == nil)
        #expect(json["output_config"] == nil)
    }

    @Test
    func `Sonnet 4_6 request keeps adaptive thinking payload`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .sonnet46, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            reasoningEffort: .medium,
            providerOptions: .init(anthropic: .init(thinking: .adaptive)),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try #require(json["thinking"] as? [String: Any])
        let outputConfig = try #require(json["output_config"] as? [String: Any])

        #expect(json["model"] as? String == "claude-sonnet-4-6")
        #expect(thinking["type"] as? String == "adaptive")
        #expect(outputConfig["effort"] as? String == "medium")
    }

    @Test
    func `Custom Anthropic request keeps thinking payload`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .custom("claude-opus-4-5-latest"), configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let request = ProviderRequest(
            messages: [.user("hi")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try #require(json["thinking"] as? [String: Any])

        #expect(json["model"] as? String == "claude-opus-4-5-latest")
        #expect(thinking["type"] as? String == "enabled")
        #expect(thinking["budget_tokens"] as? Int == 12000)
    }

    @Test
    func `Provider respects custom baseURL`() throws {
        let config = TachikomaConfiguration(
            apiKeys: ["anthropic": "test-key"],
            baseURLs: ["anthropic": "https://entropic.example/v1"],
        )
        let provider = try AnthropicProvider(model: .opus45, configuration: config)

        let request = ProviderRequest(messages: [.user("hi")])
        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        #expect(urlRequest.url?.absoluteString == "https://entropic.example/v1/messages")
    }

    @Test
    func `Provider includes additional proxy headers`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(
            model: .opus45,
            configuration: config,
            additionalHeaders: [
                "client_id": "proxy-client",
                "client_secret": "proxy-secret",
            ],
        )

        let request = ProviderRequest(messages: [.user("hi")])
        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        #expect(urlRequest.value(forHTTPHeaderField: "client_id") == "proxy-client")
        #expect(urlRequest.value(forHTTPHeaderField: "client_secret") == "proxy-secret")
    }

    @Test
    func `Stream delta decodes thinking_delta payload`() throws {
        let data = try #require("{\"type\":\"thinking_delta\",\"thinking\":\"ok\"}".data(using: .utf8))
        let delta = try JSONDecoder().decode(AnthropicStreamDelta.self, from: data)
        #expect(delta.type == "thinking_delta")
        #expect(delta.thinking == "ok")
        #expect(delta.text == nil)
    }

    @Test
    func `Stream delta decodes signature_delta payload`() throws {
        let data = try #require("{\"type\":\"signature_delta\",\"signature\":\"sig\"}".data(using: .utf8))
        let delta = try JSONDecoder().decode(AnthropicStreamDelta.self, from: data)
        #expect(delta.type == "signature_delta")
        #expect(delta.signature == "sig")
    }

    @Test
    func `Signed thinking blocks are preserved for assistant messages`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus45, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let signedThinking = ModelMessage(
            role: .assistant,
            content: [.text("thinking text")],
            channel: .thinking,
            metadata: .init(customData: [
                "anthropic.thinking.signature": "sig",
                "anthropic.thinking.type": "thinking",
            ]),
        )

        let request = ProviderRequest(
            messages: [.user("hi"), signedThinking, .assistant("hello")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 2) // signed thinking is merged into the assistant message

        let assistant = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(assistant.first?["type"] as? String == "thinking")
        #expect(assistant.first?["thinking"] as? String == "thinking text")
        #expect(assistant.first?["signature"] as? String == "sig")
    }

    @Test
    func `Redacted thinking blocks preserve signature without text`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus45, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let redacted = ModelMessage(
            role: .assistant,
            content: [.text("")],
            channel: .thinking,
            metadata: .init(customData: [
                "anthropic.thinking.signature": "sig-redacted",
                "anthropic.thinking.type": "redacted_thinking",
            ]),
        )

        let request = ProviderRequest(
            messages: [.user("hi"), redacted, .assistant("hello")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])

        let assistant = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(assistant.first?["type"] as? String == "redacted_thinking")
        #expect((assistant.first?["redacted_thinking"] as? String)?.isEmpty == true)
        #expect(assistant.first?["signature"] as? String == "sig-redacted")
    }

    @Test
    func `Thinking stays enabled even without signed history`() throws {
        let config = TachikomaConfiguration(apiKeys: ["anthropic": "test-key"])
        let provider = try AnthropicProvider(model: .opus45, configuration: config)

        let settings = GenerationSettings(
            maxTokens: 64,
            providerOptions: .init(anthropic: .init(thinking: .enabled(budgetTokens: 12000))),
        )

        let request = ProviderRequest(
            messages: [.user("hi"), .assistant("hello")],
            settings: settings,
        )

        let urlRequest = try provider.makeURLRequest(for: request, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "enabled")
        #expect(thinking["budget_tokens"] as? Int == 12000)

        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistant = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(assistant.first?["type"] as? String == "text")
    }
}
