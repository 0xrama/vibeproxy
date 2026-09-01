import XCTest
@testable import CLIProxyMenuBar

final class ConfigComposerTests: XCTestCase {
    func testPreservesRuntimeEditedTopLevelAPIKeysWhenBaseDoesNotDefineThem() {
        let root: [String: Any] = ["port": 8318]
        let runtimeRoot: [String: Any] = [
            "api-keys": ["local-key"],
            "port": 9000
        ]

        let result = ConfigComposer.preservingRuntimeEditableTopLevelKeys(
            in: root,
            from: runtimeRoot
        )

        XCTAssertEqual(result["api-keys"] as? [String], ["local-key"])
        XCTAssertEqual(result["port"] as? Int, 8318)
    }

    func testDoesNotOverwriteExplicitTopLevelAPIKeys() {
        let root: [String: Any] = ["api-keys": ["configured-key"]]
        let runtimeRoot: [String: Any] = ["api-keys": ["runtime-key"]]

        let result = ConfigComposer.preservingRuntimeEditableTopLevelKeys(
            in: root,
            from: runtimeRoot
        )

        XCTAssertEqual(result["api-keys"] as? [String], ["configured-key"])
    }

    func testDefaultZAIModelsIncludeGLM53() {
        let composed = ConfigComposer.composeRuntimeConfig(
            baseRoot: [:],
            reservedCustomProviderKeys: [],
            disabledCustomProviderIDs: [],
            disabledOAuthProviderKeys: [],
            zaiAPIKeys: ["test-key"],
            customProviderAuthRecords: [],
            includeManagedZAIProvider: true
        )

        let openAICompatibility = ConfigComposer.stringKeyedDictionaryArray(composed["openai-compatibility"])
        let zaiEntry = openAICompatibility.first { ($0["name"] as? String) == "zai" }
        XCTAssertNotNil(zaiEntry, "managed ZAI provider should be present when keys exist")

        let models = ConfigComposer.stringKeyedDictionaryArray(zaiEntry?["models"])
        let modelNames = models.compactMap { $0["name"] as? String }
        XCTAssertTrue(modelNames.contains("glm-5.3"), "glm-5.3 should be a default ZAI model")
        XCTAssertTrue(modelNames.contains("glm-5.3-flash"), "glm-5.3-flash should be a default ZAI model")
        XCTAssertEqual(modelNames.first, "glm-5.3")
    }

    func testUpsertAndRemoveUserProviderEntry() {
        var userRoot: [String: Any] = [:]
        let entry = ConfigComposer.makeUserProviderEntry(
            providerID: "my-relay",
            title: "My Relay",
            baseURL: "https://api.example.com/v1",
            models: [(name: "model-a", alias: "a")]
        )

        ConfigComposer.upsertUserProviderEntry(entry, in: &userRoot)
        var entries = ConfigComposer.stringKeyedDictionaryArray(userRoot["openai-compatibility"])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["name"] as? String, "my-relay")
        XCTAssertEqual((entries.first?["display-name"] as? String), "My Relay")

        // Upserting the same name replaces instead of duplicating.
        var updatedEntry = entry
        updatedEntry["base-url"] = "https://api2.example.com/v1"
        ConfigComposer.upsertUserProviderEntry(updatedEntry, in: &userRoot)
        entries = ConfigComposer.stringKeyedDictionaryArray(userRoot["openai-compatibility"])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["base-url"] as? String, "https://api2.example.com/v1")

        XCTAssertTrue(ConfigComposer.removeUserProviderEntry(providerID: "my-relay", from: &userRoot))
        XCTAssertNil(userRoot["openai-compatibility"])
        XCTAssertFalse(ConfigComposer.removeUserProviderEntry(providerID: "my-relay", from: &userRoot))
    }

    func testParseModelSpecs() {
        let single = ConfigComposer.parseModelSpecs("glm-5.3")
        XCTAssertNil(single.error)
        XCTAssertEqual(single.models, [(name: "glm-5.3", alias: "glm-5.3")])

        let withAliases = ConfigComposer.parseModelSpecs("Qwen/Qwen3.8-Max = cc-qwen-max\n  glm-5.3 \n")
        XCTAssertNil(withAliases.error)
        XCTAssertEqual(withAliases.models.count, 2)
        XCTAssertEqual(withAliases.models[0].name, "Qwen/Qwen3.8-Max")
        XCTAssertEqual(withAliases.models[0].alias, "cc-qwen-max")
        XCTAssertEqual(withAliases.models[1].alias, "glm-5.3")

        let empty = ConfigComposer.parseModelSpecs("   \n")
        XCTAssertNotNil(empty.error)

        let malformed = ConfigComposer.parseModelSpecs("a = b = c")
        XCTAssertNotNil(malformed.error)
    }

    func testSlugifiedProviderID() {
        XCTAssertEqual(ConfigComposer.slugifiedProviderID(fromTitle: "My Relay"), "my-relay")
        XCTAssertEqual(ConfigComposer.slugifiedProviderID(fromTitle: "OpenRouter 2"), "openrouter-2")
        XCTAssertNil(ConfigComposer.slugifiedProviderID(fromTitle: "!!!"))
    }
}
