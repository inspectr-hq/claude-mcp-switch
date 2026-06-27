import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct ClaudeDesktopConfig: Codable, Equatable {
    var values: [String: JSONValue]

    init(values: [String: JSONValue] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.values = try container.decode([String: JSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var orderedValues: [String: JSONValue] = [:]

        if let mcpServers = values["mcpServers"] {
            orderedValues["mcpServers"] = mcpServers
        }

        for key in values.keys.filter({ $0 != "mcpServers" }).sorted() {
            orderedValues[key] = values[key]
        }

        try container.encode(orderedValues)
    }

    var mcpServers: [String: MCPServerConfig] {
        guard case .object(let serversObject) = values["mcpServers"] else {
            return [:]
        }

        let decoder = JSONDecoder()
        return serversObject.reduce(into: [:]) { result, entry in
            guard case .object(let rawConfig) = entry.value else {
                return
            }

            if let data = try? JSONEncoder().encode(rawConfig),
               let config = try? decoder.decode(MCPServerConfig.self, from: data) {
                result[entry.key] = config
            }
        }
    }

    mutating func setMCPServers(_ servers: [String: MCPServerConfig]) {
        let encoder = JSONEncoder()
        values["mcpServers"] = .object(
            servers.reduce(into: [:]) { result, entry in
                let encoded = try? encoder.encode(entry.value)
                let decoded = encoded.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
                if case .object(let object)? = decoded {
                    result[entry.key] = .object(object)
                }
            }
        )
    }
}
