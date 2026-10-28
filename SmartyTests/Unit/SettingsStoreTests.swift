import XCTest
@testable import Smarty

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultAnswerModelIsGPT56Sol() {
        XCTAssertEqual(AppSettings.default.provider, .openAI)
        XCTAssertEqual(AppSettings.default.model, "gpt-5.6-sol")
        XCTAssertEqual(AIProvider.openAI.defaultModels.first, "gpt-5.6-sol")
        XCTAssertFalse(AIProvider.openAI.supportsTemperature("gpt-5.6-sol"))
    }

    func testMigratesFormerOpenAIDefaultToGPT56Sol() throws {
        let keychain = FakeKeychain()
        let suite = "smarty.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var legacy = AppSettings.default
        legacy.model = "gpt-4o-mini"
        defaults.set(try JSONEncoder().encode(legacy), forKey: "smarty.settings")

        let store = SettingsStore(defaults: defaults, keychain: keychain)

        XCTAssertEqual(store.settings.model, "gpt-5.6-sol")
    }

    func testSaveAndReloadAPIKey() {
        let keychain = FakeKeychain()
        let suite = "smarty.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        XCTAssertFalse(store.hasAPIKey)

        let result = store.saveAPIKey(" sk-test-123 ", for: .openAI)
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(store.hasAPIKey)
        XCTAssertEqual(store.apiKey, "sk-test-123")

        store.reloadAPIKeysFromKeychain()
        XCTAssertEqual(store.apiKey, "sk-test-123")

        _ = store.saveAPIKey("", for: .openAI)
        XCTAssertFalse(store.hasAPIKey)
    }

    func testKeysAreIndependentPerProvider() {
        let keychain = FakeKeychain()
        let suite = "smarty.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = SettingsStore(defaults: defaults, keychain: keychain)
        _ = store.saveAPIKey("sk-openai", for: .openAI)
        _ = store.saveAPIKey("sk-anthropic", for: .anthropic)

        XCTAssertEqual(store.apiKey(for: .openAI), "sk-openai")
        XCTAssertEqual(store.apiKey(for: .anthropic), "sk-anthropic")
        XCTAssertFalse(store.hasAPIKey(for: .gemini))
    }

    func testDecodesNewPresetFieldsWithDefaults() throws {
        let json = """
        {"model":"gpt-4o-mini","temperature":0.5}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.preferredProgrammingLanguage, .python)
        XCTAssertEqual(settings.interviewFocus, .mixed)
        XCTAssertEqual(settings.answerLength, .standard)
        XCTAssertEqual(settings.roleProfile, .default)
    }

    func testRoundTripsPresetFields() throws {
        var settings = AppSettings.default
        settings.preferredProgrammingLanguage = .rust
        settings.interviewFocus = .systemDesign
        settings.answerLength = .deep
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.preferredProgrammingLanguage, .rust)
        XCTAssertEqual(decoded.interviewFocus, .systemDesign)
        XCTAssertEqual(decoded.answerLength, .deep)
    }

    func testDecodesRoleProfileSavedBeforeCodingPreference() throws {
        // A profile written by the previous build has no codingPreference key.
        // It must still load — throwing here would reset every other setting too.
        let json = """
        {"model":"gpt-4o","roleProfile":{"title":"Data Annotator","field":"product","company":"","notes":"n"}}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.roleProfile.title, "Data Annotator")
        XCTAssertEqual(settings.roleProfile.field, .product)
        XCTAssertEqual(settings.roleProfile.codingPreference, .auto)
        XCTAssertEqual(settings.model, "gpt-4o")
    }

    func testRoundTripsRoleProfile() throws {
        var settings = AppSettings.default
        settings.roleProfile = RoleProfile(
            title: "Growth Marketing Manager",
            field: .marketing,
            company: "Acme",
            notes: "Lifecycle + paid social."
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.roleProfile.title, "Growth Marketing Manager")
        XCTAssertEqual(decoded.roleProfile.field, .marketing)
        XCTAssertEqual(decoded.roleProfile.company, "Acme")
        XCTAssertFalse(decoded.roleProfile.expectsCoding)
        XCTAssertEqual(decoded.roleProfile.displaySummary, "Marketing / growth")
        XCTAssertEqual(decoded.roleProfile.notes, "Lifecycle + paid social.")
    }

    func testMigratesEmptySoftwareRoleToGeneral() throws {
        let keychain = FakeKeychain()
        let suite = "smarty.tests.settings.role.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var legacy = AppSettings.default
        legacy.roleProfile = RoleProfile(field: .software)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "smarty.settings")

        let store = SettingsStore(defaults: defaults, keychain: keychain)

        XCTAssertEqual(store.settings.roleProfile.field, .general)
    }

    func testDoesNotMigrateNamedSoftwareRole() throws {
        let keychain = FakeKeychain()
        let suite = "smarty.tests.settings.rolekeep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var legacy = AppSettings.default
        legacy.roleProfile = RoleProfile(title: "Backend Engineer", field: .software)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "smarty.settings")

        let store = SettingsStore(defaults: defaults, keychain: keychain)

        XCTAssertEqual(store.settings.roleProfile.field, .software)
        XCTAssertEqual(store.settings.roleProfile.title, "Backend Engineer")
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
