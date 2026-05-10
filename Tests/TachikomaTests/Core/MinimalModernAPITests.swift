import Foundation
import Testing
@testable import Tachikoma
@testable import TachikomaAgent

struct MinimalModernAPITests {
    // MARK: - Model Tests

    @Test
    func `Model enum construction`() {
        // Test that model enums can be constructed
        let openaiModel = Model.openai(.gpt55)
        let anthropicModel = Model.anthropic(.opus47)
        _ = Model.grok(.grok43)
        _ = Model.ollama(.llama33)

        // Test that they can be used in a switch statement
        switch openaiModel {
        case .openai:
            break // Expected
        default:
            Issue.record("Expected OpenAI model")
        }

        switch anthropicModel {
        case .anthropic:
            break // Expected
        default:
            Issue.record("Expected Anthropic model")
        }
    }

    @Test
    func `Model default value`() {
        let defaultModel = Model.default
        // Should compile without errors
        switch defaultModel {
        case .anthropic(.opus47):
            break // Expected default
        default:
            Issue.record("Expected default to be Anthropic Opus 4.7")
        }
    }

    // MARK: - Tool System Tests

    @Test
    func `AgentTool creation`() {
        let tool = Tachikoma.createTool(
            name: "test_tool",
            description: "A test tool",
            parameters: [],
            required: [],
        ) { _ in
            AnyAgentToolValue(string: "Tool executed")
        }

        #expect(tool.name == "test_tool")
        #expect(tool.description == "A test tool")
    }

    @Test
    func `AgentToolArguments parsing`() throws {
        let args = AgentToolArguments([
            "name": AnyAgentToolValue(string: "test"),
            "value": AnyAgentToolValue(int: 42),
        ])

        #expect(try args.stringValue("name") == "test")
        #expect(try args.integerValue("value") == 42)
        #expect(args.optionalStringValue("missing") == nil)
        #expect(args.optionalStringValue("missing") ?? "default" == "default")
    }

    @Test
    func `Built-in tools exist`() {
        // Test that built-in tools are available
        #expect(weatherTool.name == "get_weather")
        #expect(timeTool.name == "get_current_time")
        #expect(calculatorTool.name == "calculate")
    }
}

// MARK: - Additional Test Code

extension MinimalModernAPITests {
    // MARK: - Error Types

    @Test
    func `Tool error types`() {
        let toolError = AgentToolError.invalidInput("test")
        #expect(toolError.errorDescription != nil)

        let tachikomaError = TachikomaError.modelNotFound("test")
        #expect(tachikomaError.errorDescription != nil)
    }

    // MARK: - Conversation Tests

    @Test
    func `Conversation basic functionality`() {
        let conversation = Conversation()
        #expect(conversation.messages.isEmpty)

        conversation.addUserMessage("Hello")
        #expect(conversation.messages.count == 1)
        #expect(conversation.messages[0].role == .user)
        #expect(conversation.messages[0].content == "Hello")

        conversation.clear()
        #expect(conversation.messages.isEmpty)
    }

    // MARK: - Basic Type Tests

    @Test
    func `ConversationMessage basic properties`() {
        let message = ConversationMessage(
            id: "test",
            role: .user,
            content: "Test",
            timestamp: Date(),
        )

        #expect(message.id == "test")
        #expect(message.role == .user)
        #expect(message.content == "Test")
    }
}
