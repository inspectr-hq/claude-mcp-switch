import Foundation
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var settings: AppSettings
    @Published var registry: ServerRegistry
    @Published var statusMessage: String?

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
            statusMessage = "Saved registry"
        } catch {
            statusMessage = "Failed to save registry: \(error.localizedDescription)"
        }
    }

    func syncToClaudeConfig() {
        do {
            try registryStore.saveRegistry(registry)
            try configStore.syncEnabledServers(from: registry)
            statusMessage = "Synced enabled servers to Claude Desktop"
        } catch {
            statusMessage = "Sync failed: \(error.localizedDescription)"
        }
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
        saveRegistry()
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
