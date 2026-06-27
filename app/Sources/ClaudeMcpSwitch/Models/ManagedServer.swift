import Foundation

struct MCPServerConfig: Codable, Equatable {
    var command: String
    var args: [String]
    var env: [String: String]

    private enum CodingKeys: String, CodingKey {
        case command
        case args
        case env
    }

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)

        if !env.isEmpty {
            try container.encode(env, forKey: .env)
        }
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
