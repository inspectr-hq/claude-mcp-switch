import Foundation

struct MCPServerConfig: Codable, Equatable {
    var command: String
    var args: [String]
    var env: [String: String]

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }
}

struct ManagedServer: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var enabled: Bool
    var config: MCPServerConfig
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        config: MCPServerConfig,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.config = config
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
