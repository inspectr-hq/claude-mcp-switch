import Foundation

struct AppSettings: Codable, Equatable {
    var claudeConfigPathOverride: String?
    var directToggleSyncToClaudeConfig: Bool = false
}
