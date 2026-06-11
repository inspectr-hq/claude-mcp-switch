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
}
