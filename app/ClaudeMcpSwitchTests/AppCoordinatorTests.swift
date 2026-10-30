import Foundation
import Testing
@testable import ClaudeMcpSwitch

@MainActor
struct AppCoordinatorTests {
    @Test(arguments: [
        ([2], 0, [2, 0, 1]),
        ([0], 3, [1, 2, 0]),
        ([0], 2, [1, 0, 2]),
        ([1], 0, [1, 0, 2]),
        ([0, 2], 3, [1, 0, 2])
    ])
    func movingServersPersistsOrderAcrossReload(
        sourceIndices: [Int], destination: Int, expectedIndices: [Int]
    ) throws {
        let harness = try CoordinatorTestHarness(isClaudeDesktopRunning: true)
        let servers = ["Alpha", "Bravo", "Charlie"].enumerated().map { index, name in
            ManagedServer(name: name, enabled: index != 1, config: MCPServerConfig(command: "npx"))
        }
        harness.coordinator.registry.servers = servers
        try harness.writeClaudeConfig("{\"mcpServers\": {\"Alpha\": {\"command\": \"npx\"}}}")
        let originalConfig = try Data(contentsOf: harness.claudeConfigURL)

        harness.coordinator.moveServers(fromOffsets: IndexSet(sourceIndices), toOffset: destination)

        let expectedIDs = expectedIndices.map { servers[$0].id }
        #expect(harness.coordinator.registry.servers.map(\.id) == expectedIDs)
        #expect(harness.coordinator.registry.servers == expectedIndices.map { servers[$0] })
        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.map(\.id) == expectedIDs)
        let reloaded = AppCoordinator(
            paths: FilePaths(fileManager: TestFileManager(appSupportURL: harness.appSupportURL), homeDirectoryURL: harness.rootURL),
            settingsDefaults: UserDefaults(suiteName: "ManualOrderReload.\(UUID().uuidString)")!,
            claudeDesktopService: TestClaudeDesktopService(isRunning: false)
        )
        #expect(reloaded.registry.servers.map(\.id) == expectedIDs)
        #expect(try Data(contentsOf: harness.claudeConfigURL) == originalConfig)
        #expect(harness.coordinator.needsClaudeDesktopRestart == false)
    }

    @Test func editingServerPreservesManualOrder() throws {
        let harness = try CoordinatorTestHarness()
        let servers = ["Zulu", "Alpha", "Middle"].map {
            ManagedServer(name: $0, config: MCPServerConfig(command: "npx"))
        }
        harness.coordinator.registry.servers = servers
        var edited = servers[1]
        edited.name = "Renamed"

        harness.coordinator.updateServer(edited)

        #expect(harness.coordinator.registry.servers.map(\.id) == servers.map(\.id))
        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.map(\.name) == ["Zulu", "Renamed", "Middle"])
    }

    @Test func duplicateServerInsertsCopyAfterSourceWithoutReorderingOthers() throws {
        let harness = try CoordinatorTestHarness()
        let servers = ["Zulu", "Alpha", "Middle"].map {
            ManagedServer(name: $0, config: MCPServerConfig(command: "npx"))
        }
        harness.coordinator.registry.servers = servers

        let duplicate = try #require(harness.coordinator.duplicateServer(servers[1].id))

        let expectedIDs = [servers[0].id, servers[1].id, duplicate.id, servers[2].id]
        #expect(harness.coordinator.registry.servers.map(\.id) == expectedIDs)
        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.map(\.id) == expectedIDs)
    }

    @Test func importingPreservesManualOrderAndAppendsNewServersAlphabetically() throws {
        let harness = try CoordinatorTestHarness()
        let servers = ["Zulu", "Alpha"].map {
            ManagedServer(name: $0, enabled: false, config: MCPServerConfig(command: "npx"))
        }
        harness.coordinator.registry.servers = servers
        try harness.writeClaudeConfig(
            """
            {"mcpServers": {
              "Charlie": {"command": "node"},
              "Zulu": {"command": "uv"},
              "Bravo": {"command": "python"}
            }}
            """
        )

        harness.coordinator.importFromClaudeConfig()

        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.map(\.name) == ["Zulu", "Alpha", "Bravo", "Charlie"])
        #expect(Array(persisted.servers.prefix(2).map(\.id)) == servers.map(\.id))
        #expect(persisted.servers.first?.config.command == "uv")
        #expect(persisted.servers.first?.enabled == true)
        #expect(persisted.servers[1].enabled == false)
    }

    @Test func updateServerPersistsEditedServer() throws {
        let harness = try CoordinatorTestHarness()
        let original = ManagedServer(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "Original",
            enabled: true,
            config: MCPServerConfig(command: "npx", args: ["old"], env: ["TOKEN": "old"]),
            notes: "before"
        )

        harness.coordinator.registry.servers = [original]

        var edited = original
        edited.name = "Edited"
        edited.config = MCPServerConfig(command: "uv", args: ["run", "edited"], env: ["TOKEN": "new"])
        edited.notes = "after"

        harness.coordinator.updateServer(edited)

        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.count == 1)
        #expect(persisted.servers[0].name == "Edited")
        #expect(persisted.servers[0].config.command == "uv")
        #expect(persisted.servers[0].config.args == ["run", "edited"])
        #expect(persisted.servers[0].notes == "after")
    }

    @Test func duplicateServerCreatesUniqueCopyAndPersistsIt() throws {
        let harness = try CoordinatorTestHarness()
        let source = ManagedServer(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            name: "TrendMiner",
            enabled: true,
            config: MCPServerConfig(command: "npx", args: ["mcp-remote"], env: [:]),
            notes: "seed"
        )

        harness.coordinator.registry.servers = [source]

        let duplicate = harness.coordinator.duplicateServer(source.id)

        #expect(duplicate != nil)
        #expect(duplicate?.name == "TrendMiner Copy")
        #expect(duplicate?.config == source.config)
        #expect(duplicate?.notes == source.notes)

        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.map(\.name).sorted() == ["TrendMiner", "TrendMiner Copy"])
    }

    @Test func deleteServerRemovesServerFromRegistry() throws {
        let harness = try CoordinatorTestHarness()
        let first = ManagedServer(name: "Keep", enabled: true, config: MCPServerConfig(command: "npx"))
        let second = ManagedServer(name: "Delete", enabled: true, config: MCPServerConfig(command: "uv"))

        harness.coordinator.registry.servers = [first, second]

        harness.coordinator.deleteServer(second.id)

        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.map(\.name) == ["Keep"])
    }

    @Test func importFromClaudeConfigLoadsServersIntoLocalList() throws {
        let harness = try CoordinatorTestHarness()
        try harness.writeClaudeConfig(
            """
            {
              "mcpServers": {
                "BatchWorks ERP": {
                  "command": "uv",
                  "args": ["run", "python", "-m", "erp_mcp_server"]
                },
                "Notion MCP": {
                  "command": "npx",
                  "args": ["-y", "@notionhq/notion-mcp-server"],
                  "env": {
                    "NOTION_TOKEN": "token"
                  }
                }
              }
            }
            """
        )

        harness.coordinator.importFromClaudeConfig()

        #expect(harness.coordinator.registry.servers.map(\.name).sorted() == ["BatchWorks ERP", "Notion MCP"])
        let persisted = try harness.loadRegistry()
        #expect(persisted.servers.count == 2)
        #expect(persisted.servers.first(where: { $0.name == "BatchWorks ERP" })?.enabled == true)
    }

    @Test func importableClaudeServerCountIgnoresAlreadyImportedServers() throws {
        let harness = try CoordinatorTestHarness()
        try harness.writeClaudeConfig(
            """
            {
              "mcpServers": {
                "Existing": {
                  "command": "node",
                  "args": ["existing.js"]
                },
                "New One": {
                  "command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-github"]
                }
              }
            }
            """
        )

        harness.coordinator.registry = ServerRegistry(servers: [
            ManagedServer(name: "Existing", enabled: true, config: MCPServerConfig(command: "node", args: ["existing.js"]))
        ])

        harness.coordinator.refreshClaudeConfigChangeCounts()

        #expect(harness.coordinator.importableClaudeServerCount == 1)
    }

    @Test func syncableClaudeServerChangeCountIgnoresRemovals() throws {
        let harness = try CoordinatorTestHarness()
        try harness.writeClaudeConfig(
            """
            {
              "mcpServers": {
                "Existing": {
                  "command": "node",
                  "args": ["existing.js"]
                },
                "Changed": {
                  "command": "python",
                  "args": ["old.py"]
                },
                "Obsolete": {
                  "command": "uv",
                  "args": ["legacy.py"]
                }
              }
            }
            """
        )

        harness.coordinator.registry = ServerRegistry(servers: [
            ManagedServer(name: "Existing", enabled: true, config: MCPServerConfig(command: "node", args: ["existing.js"])),
            ManagedServer(name: "Changed", enabled: true, config: MCPServerConfig(command: "python", args: ["new.py"])),
            ManagedServer(name: "New", enabled: true, config: MCPServerConfig(command: "npx"))
        ])

        harness.coordinator.refreshClaudeConfigChangeCounts()

        #expect(harness.coordinator.syncableClaudeServerChangeCount == 2)
    }

    @Test func confirmSyncWritesEnabledServersToClaudeConfig() throws {
        let harness = try CoordinatorTestHarness()
        try harness.writeClaudeConfig(
            """
            {
              "theme": "dark",
              "mcpServers": {
                "Legacy": {
                  "command": "node",
                  "args": ["legacy.js"]
                }
              }
            }
            """
        )

        harness.coordinator.registry = ServerRegistry(servers: [
            ManagedServer(name: "GitHub", enabled: true, config: MCPServerConfig(command: "npx", args: ["-y", "@modelcontextprotocol/server-github"])),
            ManagedServer(name: "Disabled", enabled: false, config: MCPServerConfig(command: "python"))
        ])

        harness.coordinator.confirmSyncToClaudeConfig()

        let config = try harness.loadClaudeConfig()
        #expect(config.values["theme"] == .string("dark"))
        #expect(config.mcpServers.keys.sorted() == ["GitHub"])
        #expect(config.mcpServers["GitHub"]?.command == "npx")
    }

    @Test func confirmSyncMarksClaudeDesktopForRestartOnlyWhenRunning() throws {
        let runningHarness = try CoordinatorTestHarness(isClaudeDesktopRunning: true)
        try runningHarness.writeClaudeConfig(
            """
            {
              "mcpServers": {}
            }
            """
        )
        runningHarness.coordinator.registry = ServerRegistry(servers: [
            ManagedServer(name: "GitHub", enabled: true, config: MCPServerConfig(command: "npx"))
        ])

        runningHarness.coordinator.confirmSyncToClaudeConfig()

        #expect(runningHarness.coordinator.needsClaudeDesktopRestart == true)
        #expect(runningHarness.coordinator.shouldShowClaudeDesktopRestartAction == true)

        let stoppedHarness = try CoordinatorTestHarness(isClaudeDesktopRunning: false)
        try stoppedHarness.writeClaudeConfig(
            """
            {
              "mcpServers": {}
            }
            """
        )
        stoppedHarness.coordinator.registry = ServerRegistry(servers: [
            ManagedServer(name: "GitHub", enabled: true, config: MCPServerConfig(command: "npx"))
        ])

        stoppedHarness.coordinator.confirmSyncToClaudeConfig()

        #expect(stoppedHarness.coordinator.needsClaudeDesktopRestart == false)
        #expect(stoppedHarness.coordinator.shouldShowClaudeDesktopRestartAction == false)
    }

    @Test func directToggleSyncUpdatesOnlyChangedServerInClaudeConfig() throws {
        let harness = try CoordinatorTestHarness()
        try harness.writeClaudeConfig(
            """
            {
              "theme": "light",
              "mcpServers": {
                "Keep": {
                  "command": "node",
                  "args": ["keep.js"]
                },
                "Target": {
                  "command": "python",
                  "args": ["old.py"]
                }
              }
            }
            """
        )

        harness.coordinator.settings.directToggleSyncToClaudeConfig = true
        let keep = ManagedServer(name: "Keep", enabled: true, config: MCPServerConfig(command: "node", args: ["keep.js"]))
        let target = ManagedServer(name: "Target", enabled: false, config: MCPServerConfig(command: "python", args: ["old.py"]))
        harness.coordinator.registry.servers = [keep, target]

        harness.coordinator.setEnabled(false, for: target.id)

        let config = try harness.loadClaudeConfig()
        #expect(config.values["theme"] == .string("light"))
        #expect(config.mcpServers.keys.sorted() == ["Keep"])
        #expect(config.mcpServers["Keep"]?.args == ["keep.js"])
    }

    @Test func directToggleSyncMarksClaudeDesktopForRestartWhenRunning() throws {
        let harness = try CoordinatorTestHarness(isClaudeDesktopRunning: true)
        try harness.writeClaudeConfig(
            """
            {
              "mcpServers": {
                "Target": {
                  "command": "python",
                  "args": ["old.py"]
                }
              }
            }
            """
        )

        harness.coordinator.settings.directToggleSyncToClaudeConfig = true
        let target = ManagedServer(name: "Target", enabled: true, config: MCPServerConfig(command: "python", args: ["old.py"]))
        harness.coordinator.registry.servers = [target]

        harness.coordinator.setEnabled(false, for: target.id)

        #expect(harness.coordinator.needsClaudeDesktopRestart == true)
        #expect(harness.coordinator.shouldShowClaudeDesktopRestartAction == true)
    }

    @Test func claudeDesktopTerminationClearsRestartReminder() throws {
        let harness = try CoordinatorTestHarness(isClaudeDesktopRunning: true)
        harness.coordinator.needsClaudeDesktopRestart = true

        harness.desktopService.emitRunningState(false)

        #expect(harness.coordinator.isClaudeDesktopRunning == false)
        #expect(harness.coordinator.needsClaudeDesktopRestart == false)
        #expect(harness.coordinator.shouldShowClaudeDesktopRestartAction == false)
    }

    @Test func restartClaudeDesktopClearsReminderAndInvokesService() async throws {
        let harness = try CoordinatorTestHarness(isClaudeDesktopRunning: true)
        harness.coordinator.needsClaudeDesktopRestart = true

        await harness.coordinator.restartClaudeDesktopToApplyChanges()

        #expect(harness.desktopService.restartCallCount == 1)
        #expect(harness.coordinator.needsClaudeDesktopRestart == false)
    }
}

@MainActor
private struct CoordinatorTestHarness {
    let rootURL: URL
    let appSupportURL: URL
    let claudeDirectoryURL: URL
    let claudeConfigURL: URL
    let desktopService: TestClaudeDesktopService
    let coordinator: AppCoordinator

    init(isClaudeDesktopRunning: Bool = false) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.rootURL = rootURL
        let libraryURL = rootURL.appendingPathComponent("Library", isDirectory: true)
        self.appSupportURL = libraryURL.appendingPathComponent("Application Support", isDirectory: true)
        self.claudeDirectoryURL = appSupportURL.appendingPathComponent("Claude", isDirectory: true)
        self.claudeConfigURL = claudeDirectoryURL.appendingPathComponent("claude_desktop_config.json")

        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDirectoryURL, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "AppCoordinatorTests.\(UUID().uuidString)")!
        let desktopService = TestClaudeDesktopService(isRunning: isClaudeDesktopRunning)
        self.desktopService = desktopService

        let fileManager = TestFileManager(appSupportURL: appSupportURL)
        let paths = FilePaths(fileManager: fileManager, homeDirectoryURL: rootURL)
        self.coordinator = AppCoordinator(
            paths: paths,
            settingsDefaults: defaults,
            claudeDesktopService: desktopService
        )
    }

    func loadRegistry() throws -> ServerRegistry {
        try coordinator.registryStore.loadRegistry()
    }

    func writeClaudeConfig(_ json: String) throws {
        try json.write(to: claudeConfigURL, atomically: true, encoding: .utf8)
    }

    func loadClaudeConfig() throws -> ClaudeDesktopConfig {
        let data = try Data(contentsOf: claudeConfigURL)
        return try JSONDecoder().decode(ClaudeDesktopConfig.self, from: data)
    }
}

private final class TestFileManager: FileManager {
    private let appSupportURL: URL

    init(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .applicationSupportDirectory, domainMask == .userDomainMask {
            return [appSupportURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

@MainActor
private final class TestClaudeDesktopService: ClaudeDesktopServicing {
    var isRunning: Bool
    var restartCallCount = 0
    private var handler: (@MainActor (Bool) -> Void)?

    init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    func setRunningStateDidChangeHandler(_ handler: (@MainActor (Bool) -> Void)?) {
        self.handler = handler
    }

    func restartClaudeDesktop() async throws {
        restartCallCount += 1
        isRunning = true
    }

    func emitRunningState(_ isRunning: Bool) {
        self.isRunning = isRunning
        handler?(isRunning)
    }
}
