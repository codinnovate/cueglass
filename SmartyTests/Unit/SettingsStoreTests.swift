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

        let result = store.saveAPIKey(" sk-test-123 ")
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(store.hasAPIKey)
        XCTAssertEqual(store.apiKey, "sk-test-123")

        store.reloadAPIKeyFromKeychain()
        XCTAssertEqual(store.apiKey, "sk-test-123")

        _ = store.saveAPIKey("")
        XCTAssertFalse(store.hasAPIKey)
    }

    func testDecodesNewPresetFieldsWithDefaults() throws {
        let json = """
        {"model":"gpt-4o-mini","temperature":0.5}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.preferredProgrammingLanguage, .python)
        XCTAssertEqual(settings.interviewFocus, .mixed)
        XCTAssertEqual(settings.answerLength, .standard)
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
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
