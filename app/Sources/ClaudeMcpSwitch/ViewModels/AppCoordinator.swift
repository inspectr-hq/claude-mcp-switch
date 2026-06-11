import Foundation
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var settings: AppSettings
    @Published var registry: ServerRegistry
    @Published var statusMessage: String?
    @Published var syncPreview: SyncPreview?
    @Published var syncRemovalWarning: SyncRemovalWarning?

    let registryStore: RegistryStore

    private let paths: FilePaths
    private let configBackupService: BackupService
    private let settingsDefaults: UserDefaults

    init(
        paths: FilePaths = FilePaths(),
        settingsDefaults: UserDefaults = .standard
    ) {
        self.paths = paths
        self.settingsDefaults = settingsDefaults
        self.registryStore = RegistryStore(
            registryURL: paths.registryURL,
            backupsDirectoryURL: paths.backupsDirectoryURL
        )
        self.configBackupService = BackupService(backupsDirectoryURL: paths.backupsDirectoryURL)
        self.settings = Self.loadSettings(from: settingsDefaults)
        self.registry = (try? registryStore.loadRegistry()) ?? ServerRegistry()
    }

    var effectiveClaudeConfigPath: String {
        effectiveClaudeConfigURL.path
    }

    private var effectiveClaudeConfigURL: URL {
        if let override = settings.claudeConfigPathOverride, !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return paths.defaultClaudeConfigURL
    }

    private var configStore: ClaudeConfigStore {
        ClaudeConfigStore(
            configURLProvider: { [effectiveClaudeConfigURL] in effectiveClaudeConfigURL },
            backupService: configBackupService
        )
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            settingsDefaults.set(data, forKey: "claude_mcp_switch.settings")
        }
    }

    func saveRegistry() {
        do {
            try registryStore.saveRegistry(registry)
            statusMessage = "Saved MCP Servers"
        } catch {
            statusMessage = "Failed to save MCP Servers: \(error.localizedDescription)"
        }
    }

    func requestSyncToClaudeConfig() {
        do {
            let currentConfig = try configStore.loadConfig()
            let enabledServers = registry.servers
                .filter(\.enabled)
                .reduce(into: [String: MCPServerConfig]()) { result, server in
                    result[server.name] = server.config
                }

            let preview = SyncPreview(
                configPath: effectiveClaudeConfigPath,
                currentServers: currentConfig.mcpServers,
                desiredServers: enabledServers
            )

            guard preview.hasChanges else {
                statusMessage = "Claude Desktop already matches the enabled MCP Servers"
                return
            }

            if !preview.additions.isEmpty || !preview.updates.isEmpty {
                syncRemovalWarning = nil
                syncPreview = preview
            } else if !preview.removals.isEmpty {
                syncPreview = nil
                syncRemovalWarning = SyncRemovalWarning(
                    configPath: effectiveClaudeConfigPath,
                    removals: preview.removals.map(\.name)
                )
            }
        } catch {
            statusMessage = "Sync preview failed: \(error.localizedDescription)"
        }
    }

    func confirmSyncToClaudeConfig() {
        do {
            try registryStore.saveRegistry(registry)
            try configStore.syncEnabledServers(from: registry)
            syncPreview = nil
            syncRemovalWarning = nil
            statusMessage = "Synced enabled servers to Claude Desktop"
        } catch {
            statusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    func cancelSyncToClaudeConfig() {
        syncPreview = nil
        syncRemovalWarning = nil
        statusMessage = "Sync cancelled"
    }

    func importFromClaudeConfig() {
        do {
            let config = try configStore.loadConfig()
            let importedServers = config.mcpServers.map { name, value in
                ManagedServer(name: name, enabled: true, config: value)
            }

            for server in importedServers {
                if let index = registry.servers.firstIndex(where: { $0.name == server.name }) {
                    registry.servers[index].config = server.config
                    registry.servers[index].enabled = true
                    registry.servers[index].updatedAt = Date()
                } else {
                    registry.servers.append(server)
                }
            }

            registry.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            try registryStore.saveRegistry(registry)
            statusMessage = "Imported \(importedServers.count) servers from Claude Desktop"
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool, for serverID: UUID) {
        guard let index = registry.servers.firstIndex(where: { $0.id == serverID }) else {
            return
        }

        registry.servers[index].enabled = enabled
        registry.servers[index].updatedAt = Date()
        let updatedServer = registry.servers[index]

        do {
            try registryStore.saveRegistry(registry)

            if settings.directToggleSyncToClaudeConfig {
                try configStore.syncServer(updatedServer)
                statusMessage = updatedServer.enabled
                    ? "Enabled MCP Server in Claude Desktop"
                    : "Disabled MCP Server in Claude Desktop"
            } else {
                statusMessage = "Saved MCP Servers"
            }
        } catch {
            statusMessage = "Failed to update MCP Server: \(error.localizedDescription)"
        }
    }

    func updateServer(_ server: ManagedServer) {
        guard let index = registry.servers.firstIndex(where: { $0.id == server.id }) else {
            return
        }

        var updatedServer = server
        updatedServer.updatedAt = Date()
        registry.servers[index] = updatedServer
        registry.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveRegistry()
    }

    func deleteServer(_ serverID: UUID) {
        let originalCount = registry.servers.count
        registry.servers.removeAll { $0.id == serverID }

        guard registry.servers.count != originalCount else {
            return
        }

        saveRegistry()
        statusMessage = "Deleted MCP Server"
    }

    private static func loadSettings(from defaults: UserDefaults) -> AppSettings {
        guard
            let data = defaults.data(forKey: "claude_mcp_switch.settings"),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }

        return settings
    }
}

struct SyncPreview: Identifiable {
    let id = UUID()
    let configPath: String
    let additions: [SyncPreviewChange]
    let updates: [SyncPreviewChange]
    let removals: [SyncPreviewChange]
    let unchangedCount: Int

    init(
        configPath: String,
        currentServers: [String: MCPServerConfig],
        desiredServers: [String: MCPServerConfig]
    ) {
        var additions: [SyncPreviewChange] = []
        var updates: [SyncPreviewChange] = []
        var removals: [SyncPreviewChange] = []
        var unchangedCount = 0

        let allNames = Set(currentServers.keys).union(desiredServers.keys)

        for name in allNames.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let current = currentServers[name]
            let desired = desiredServers[name]

            switch (current, desired) {
            case let (nil, .some(desiredConfig)):
                additions.append(
                    SyncPreviewChange(name: name, currentConfig: nil, desiredConfig: desiredConfig)
                )
            case let (.some(currentConfig), nil):
                removals.append(
                    SyncPreviewChange(name: name, currentConfig: currentConfig, desiredConfig: nil)
                )
            case let (.some(currentConfig), .some(desiredConfig)):
                if currentConfig == desiredConfig {
                    unchangedCount += 1
                } else {
                    updates.append(
                        SyncPreviewChange(
                            name: name,
                            currentConfig: currentConfig,
                            desiredConfig: desiredConfig
                        )
                    )
                }
            case (nil, nil):
                break
            }
        }

        self.configPath = configPath
        self.additions = additions
        self.updates = updates
        self.removals = removals
        self.unchangedCount = unchangedCount
    }

    var currentCount: Int {
        updates.count + removals.count + unchangedCount
    }

    var desiredCount: Int {
        additions.count + updates.count + unchangedCount
    }

    var changeCount: Int {
        additions.count + updates.count + removals.count
    }

    var hasChanges: Bool {
        changeCount > 0
    }
}

struct SyncPreviewChange: Identifiable {
    let id = UUID()
    let name: String
    let currentConfig: MCPServerConfig?
    let desiredConfig: MCPServerConfig?
}

struct SyncRemovalWarning: Identifiable {
    let id = UUID()
    let configPath: String
    let removals: [String]

    var title: String {
        removals.count == 1 ? "Remove 1 Server From Claude Desktop?" : "Remove \(removals.count) Servers From Claude Desktop?"
    }

    var message: String {
        let names = removals.joined(separator: ", ")
        return "Claude Desktop currently contains these MCP servers: \(names). They are not enabled in Claude MCP Switch, so approving sync will remove them from Claude Desktop's servers list."
    }
}
