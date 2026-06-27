import Foundation

struct AppSettings: Codable, Equatable {
    var claudeConfigPathOverride: String?
    var directToggleSyncToClaudeConfig: Bool

    init(
        claudeConfigPathOverride: String? = nil,
        directToggleSyncToClaudeConfig: Bool = true
    ) {
        self.claudeConfigPathOverride = claudeConfigPathOverride
        self.directToggleSyncToClaudeConfig = directToggleSyncToClaudeConfig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claudeConfigPathOverride = try container.decodeIfPresent(String.self, forKey: .claudeConfigPathOverride)
        directToggleSyncToClaudeConfig = try container.decodeIfPresent(
            Bool.self,
            forKey: .directToggleSyncToClaudeConfig
        ) ?? true
    }
}
