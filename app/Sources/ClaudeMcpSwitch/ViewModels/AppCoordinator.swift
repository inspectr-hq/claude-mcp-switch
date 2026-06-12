import Foundation
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var settings: AppSettings
    @Published var registry: ServerRegistry
    @Published var statusMessage: String?
    @Published var syncPreview: SyncPreview?
    @Published var syncRemovalWarning: SyncRemovalWarning?
    @Published var isClaudeDesktopRunning: Bool
    @Published var needsClaudeDesktopRestart: Bool = false

    let registryStore: RegistryStore

    private let paths: FilePaths
    private let configBackupService: BackupService
    private let settingsDefaults: UserDefaults
    private let claudeDesktopService: ClaudeDesktopServicing

    init(
        paths: FilePaths = FilePaths(),
        settingsDefaults: UserDefaults = .standard,
        claudeDesktopService: ClaudeDesktopServicing? = nil
    ) {
        self.paths = paths
        self.settingsDefaults = settingsDefaults
        let resolvedClaudeDesktopService = claudeDesktopService ?? ClaudeDesktopService()
        self.claudeDesktopService = resolvedClaudeDesktopService
        self.registryStore = RegistryStore(
            registryURL: paths.registryURL,
            backupsDirectoryURL: paths.backupsDirectoryURL
        )
        self.configBackupService = BackupService(backupsDirectoryURL: paths.backupsDirectoryURL)
        self.settings = Self.loadSettings(from: settingsDefaults)
        self.registry = (try? registryStore.loadRegistry()) ?? ServerRegistry()
        self.isClaudeDesktopRunning = resolvedClaudeDesktopService.isRunning
        resolvedClaudeDesktopService.setRunningStateDidChangeHandler { [weak self] isRunning in
            self?.handleClaudeDesktopRunningStateChange(isRunning)
        }
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
            markClaudeDesktopNeedsRestartIfRunning(
                baseStatusMessage: "Synced enabled servers to Claude Desktop"
            )
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
                markClaudeDesktopNeedsRestartIfRunning(
                    baseStatusMessage: updatedServer.enabled
                        ? "Enabled MCP Server in Claude Desktop"
                        : "Disabled MCP Server in Claude Desktop"
                )
            } else {
                statusMessage = "Saved MCP Servers"
            }
        } catch {
            statusMessage = "Failed to update MCP Server: \(error.localizedDescription)"
        }
    }

    func restartClaudeDesktopToApplyChanges() async {
        guard needsClaudeDesktopRestart, isClaudeDesktopRunning else {
            return
        }

        do {
            try await claudeDesktopService.restartClaudeDesktop()
            needsClaudeDesktopRestart = false
            statusMessage = "Restarted Claude Desktop to apply changes"
        } catch {
            statusMessage = "Claude Desktop restart failed: \(error.localizedDescription)"
        }
    }

    var shouldShowClaudeDesktopRestartAction: Bool {
        needsClaudeDesktopRestart && isClaudeDesktopRunning
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

    func duplicateServer(_ serverID: UUID) -> ManagedServer? {
        guard let sourceServer = registry.servers.first(where: { $0.id == serverID }) else {
            return nil
        }

        let duplicate = ManagedServer(
            name: uniqueDuplicateName(for: sourceServer.name),
            enabled: sourceServer.enabled,
            config: sourceServer.config,
            notes: sourceServer.notes
        )

        registry.servers.append(duplicate)
        registry.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveRegistry()
        statusMessage = "Duplicated MCP Server"
        return duplicate
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

    private func uniqueDuplicateName(for sourceName: String) -> String {
        let existingNames = Set(registry.servers.map(\.name))
        let baseName = "\(sourceName) Copy"

        guard existingNames.contains(baseName) else {
            return baseName
        }

        var index = 2
        while existingNames.contains("\(baseName) \(index)") {
            index += 1
        }

        return "\(baseName) \(index)"
    }

    private func markClaudeDesktopNeedsRestartIfRunning(baseStatusMessage: String) {
        if isClaudeDesktopRunning {
            needsClaudeDesktopRestart = true
            statusMessage = "\(baseStatusMessage). Restart Claude Desktop to apply changes."
        } else {
            statusMessage = baseStatusMessage
        }
    }

    private func handleClaudeDesktopRunningStateChange(_ isRunning: Bool) {
        isClaudeDesktopRunning = isRunning
        if !isRunning {
            needsClaudeDesktopRestart = false
        }
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
        "These MCP Servers exist in Claude Desktop, but are not enabled in Claude MCP Switch. Approving sync will remove them from Claude Desktop."
    }
}
