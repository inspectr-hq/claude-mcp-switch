import Foundation
import Testing
@testable import ClaudeMcpSwitch

struct AppSettingsTests {
    @Test func codableRoundTripPreservesOverridePath() throws {
        let settings = AppSettings(
            claudeConfigPathOverride: "/tmp/custom-claude.json"
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded == settings)
    }

    @Test func codableRoundTripPreservesDirectToggleSyncPreference() throws {
        let settings = AppSettings(
            claudeConfigPathOverride: "/tmp/custom-claude.json",
            directToggleSyncToClaudeConfig: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded == settings)
    }

    @Test func missingDirectToggleSyncPreferenceDefaultsToEnabled() throws {
        let data = """
        {
          "claudeConfigPathOverride": "/tmp/custom-claude.json"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.directToggleSyncToClaudeConfig == true)
    }
}
