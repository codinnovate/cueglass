import XCTest
@testable import Smarty

@MainActor
final class SettingsStoreTests: XCTestCase {
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
        XCTAssertEqual(decoded.roleProfile.displaySummary, "Growth Marketing Manager at Acme")
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
