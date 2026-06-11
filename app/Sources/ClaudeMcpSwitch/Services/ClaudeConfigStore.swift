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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
