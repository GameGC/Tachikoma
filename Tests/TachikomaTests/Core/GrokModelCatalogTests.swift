import Foundation
import Testing
@testable import Tachikoma

struct GrokModelCatalogTests {
    private static let catalog: [Model.Grok] = [
        .grok43,
        .grok420MultiAgent,
        .grok420Reasoning,
        .grok420NonReasoning,
    ]

    private func requireModernPlatforms(_ body: () throws -> Void) rethrows {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            try body()
        } else {
            Issue.record("ModelSelector requires macOS 13.0+ / iOS 16.0+")
        }
    }

    @Test
    func `CaseIterable reflects the official Grok catalog`() {
        self.requireModernPlatforms {
            #expect(Model.Grok.allCases == Self.catalog)
        }
    }

    @Test
    func `ModelSelector parses every Grok model identifier`() throws {
        try self.requireModernPlatforms {
            for model in Self.catalog {
                let parsed = try ModelSelector.parseModel(model.modelId)
                #expect(parsed == .grok(model))
            }
            #expect(try ModelSelector.parseModel("grok-4.3-latest") == .grok(.grok43))
        }
    }

    @Test
    func `Available-model CLI listing matches catalog IDs`() {
        self.requireModernPlatforms {
            let listed = Set(ModelSelector.availableModels(for: "grok"))
            let expected = Set(Self.catalog.map(\.modelId))
            #expect(listed == expected)
        }
    }

    @Test
    func `Current Grok text models do not advertise vision`() {
        self.requireModernPlatforms {
            for model in Self.catalog {
                let languageModel = Model.grok(model)
                #expect(languageModel.supportsVision == false)
            }
        }
    }

    @Test
    func `ModelSelector rejects retired Grok identifiers`() {
        self.requireModernPlatforms {
            for id in ["grok-4-0709", "grok-3", "grok-2-1212", "grok-4-fast", "grok-code-fast-1"] {
                #expect(throws: ModelValidationError.self) {
                    _ = try ModelSelector.parseModel(id)
                }
            }
        }
    }

    @Test
    func `ModelSelector preserves provider-qualified Grok slugs as OpenRouter IDs`() throws {
        try self.requireModernPlatforms {
            let parsed = try ModelSelector.parseModel("xai/grok-code-fast-1")

            #expect(parsed == .openRouter(modelId: "xai/grok-code-fast-1"))
        }
    }
}
