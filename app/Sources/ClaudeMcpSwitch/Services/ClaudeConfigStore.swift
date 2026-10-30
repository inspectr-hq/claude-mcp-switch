import Foundation

protocol ClaudeConfigStoreProtocol {
    func loadConfig() throws -> ClaudeDesktopConfig
    func syncEnabledServers(from registry: ServerRegistry) throws
    func syncServer(_ server: ManagedServer) throws
}

struct ClaudeConfigStore: ClaudeConfigStoreProtocol {
    let configURLProvider: () -> URL
    private let fileManager: FileManager
    private let backupService: BackupService

    init(
        configURLProvider: @escaping () -> URL,
        fileManager: FileManager = .default,
        backupService: BackupService
    ) {
        self.configURLProvider = configURLProvider
        self.fileManager = fileManager
        self.backupService = backupService
    }

    func loadConfig() throws -> ClaudeDesktopConfig {
        let url = configURLProvider()
        guard fileManager.fileExists(atPath: url.path) else {
            return ClaudeDesktopConfig()
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ClaudeDesktopConfig.self, from: data)
    }

    func syncEnabledServers(from registry: ServerRegistry) throws {
        var config = try loadConfig()
        let enabledServers = registry.servers
            .filter(\.enabled)
            .reduce(into: [String: MCPServerConfig]()) { result, server in
                result[server.name] = server.config
            }
        config.setMCPServers(enabledServers)

        let url = configURLProvider()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backupService.createBackupIfNeeded(sourceURL: url, prefix: "claude_desktop_config")
        try write(config: config, to: url)
    }

    func syncServer(_ server: ManagedServer) throws {
        var config = try loadConfig()
        var currentServers = config.mcpServers

        if server.enabled {
            currentServers[server.name] = server.config
        } else {
            currentServers.removeValue(forKey: server.name)
        }

        config.setMCPServers(currentServers)

        let url = configURLProvider()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backupService.createBackupIfNeeded(sourceURL: url, prefix: "claude_desktop_config")
        try write(config: config, to: url)
    }

    private func write(config: ClaudeDesktopConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        // JSONEncoder does not preserve dictionary insertion order. Assemble the
        // top-level members explicitly, leaving JSON escaping and values to it.
        let keys = ["mcpServers"] + config.values.keys.filter { $0 != "mcpServers" }.sorted()
        let members = try keys.compactMap { key -> String? in
            guard let value = config.values[key] else { return nil }
            let encodedKey = String(decoding: try encoder.encode(key), as: UTF8.self)
            let encodedValue = String(decoding: try encoder.encode(value), as: UTF8.self)
                .replacingOccurrences(of: "\n", with: "\n  ")
            return "  \(encodedKey) : \(encodedValue)"
        }
        let json = members.isEmpty ? "{}" : "{\n\(members.joined(separator: ",\n"))\n}"
        let data = Data(json.utf8)
        try data.write(to: url, options: .atomic)
    }
}
