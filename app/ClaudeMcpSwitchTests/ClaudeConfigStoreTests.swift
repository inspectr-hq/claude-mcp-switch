import Foundation
import Testing
@testable import ClaudeMcpSwitch

struct ClaudeConfigStoreTests {
    @Test func loadConfigImportsServersWithoutEnvBlocks() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let claudeURL = tempRoot.appendingPathComponent("claude_desktop_config.json")
        let original = """
        {
          "mcpServers": {
            "BatchWorks ERP": {
              "command": "uv",
              "args": ["run", "python", "-m", "erp_mcp_server"]
            },
            "notionApi": {
              "command": "npx",
              "args": ["-y", "@notionhq/notion-mcp-server"],
              "env": {
                "NOTION_TOKEN": "token"
              }
            }
          }
        }
        """
        try original.write(to: claudeURL, atomically: true, encoding: .utf8)

        let store = ClaudeConfigStore(
            configURLProvider: { claudeURL },
            backupService: BackupService(backupsDirectoryURL: tempRoot.appendingPathComponent("backups", isDirectory: true))
        )

        let config = try store.loadConfig()

        #expect(config.mcpServers.keys.sorted() == ["BatchWorks ERP", "notionApi"])
        #expect(config.mcpServers["BatchWorks ERP"]?.env == [:])
        #expect(config.mcpServers["notionApi"]?.env == ["NOTION_TOKEN": "token"])
    }

    @Test func syncPreservesUnrelatedTopLevelKeys() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let claudeURL = tempRoot.appendingPathComponent("claude_desktop_config.json")
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)
        let original = """
        {
          "theme": "dark",
          "autoUpdates": false,
          "mcpServers": {
            "legacy": {
              "command": "node",
              "args": ["legacy.js"]
            }
          }
        }
        """
        try original.write(to: claudeURL, atomically: true, encoding: .utf8)

        let store = ClaudeConfigStore(
            configURLProvider: { claudeURL },
            backupService: BackupService(backupsDirectoryURL: backupsURL)
        )

        let registry = ServerRegistry(servers: [
            ManagedServer(
                name: "github",
                enabled: true,
                config: MCPServerConfig(
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-github"],
                    env: ["TOKEN": "value"]
                )
            ),
            ManagedServer(
                name: "disabled",
                enabled: false,
                config: MCPServerConfig(command: "python")
            )
        ])

        try store.syncEnabledServers(from: registry)

        let data = try Data(contentsOf: claudeURL)
        let config = try JSONDecoder().decode(ClaudeDesktopConfig.self, from: data)

        #expect(config.values["theme"] == .string("dark"))
        #expect(config.values["autoUpdates"] == .bool(false))
        #expect(config.mcpServers.keys.sorted() == ["github"])
        #expect(config.mcpServers["github"]?.command == "npx")
    }

    @Test func syncDoesNotEscapeForwardSlashesInWrittenJSON() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let claudeURL = tempRoot.appendingPathComponent("claude_desktop_config.json")
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)
        try "{}".write(to: claudeURL, atomically: true, encoding: .utf8)

        let store = ClaudeConfigStore(
            configURLProvider: { claudeURL },
            backupService: BackupService(backupsDirectoryURL: backupsURL)
        )

        let registry = ServerRegistry(servers: [
            ManagedServer(
                name: "TrendMiner CS",
                enabled: true,
                config: MCPServerConfig(
                    command: "npx",
                    args: [
                        "mcp-remote@0.1.37",
                        "https://tm-mcp-cs.in-spectr.dev/mcp"
                    ]
                )
            )
        ])

        try store.syncEnabledServers(from: registry)

        let writtenJSON = try String(contentsOf: claudeURL, encoding: .utf8)
        #expect(writtenJSON.contains("https://tm-mcp-cs.in-spectr.dev/mcp"))
        #expect(!writtenJSON.contains("https:\\/\\/tm-mcp-cs.in-spectr.dev\\/mcp"))
    }

    @Test(arguments: [false, true])
    func syncWritesMCPServersBeforeOtherTopLevelKeys(directToggle: Bool) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let claudeURL = tempRoot.appendingPathComponent("claude_desktop_config.json")
        let backupsURL = tempRoot.appendingPathComponent("backups", isDirectory: true)
        let original = """
        {
          "theme": "dark",
          "autoUpdates": false,
          "mcpServers": {
            "legacy": {
              "command": "node",
              "args": ["legacy.js"]
            }
          }
        }
        """
        try original.write(to: claudeURL, atomically: true, encoding: .utf8)

        let store = ClaudeConfigStore(
            configURLProvider: { claudeURL },
            backupService: BackupService(backupsDirectoryURL: backupsURL)
        )

        let registry = ServerRegistry(servers: [
            ManagedServer(
                name: "github",
                enabled: true,
                config: MCPServerConfig(command: "npx")
            )
        ])

        if directToggle {
            try store.syncServer(registry.servers[0])
        } else {
            try store.syncEnabledServers(from: registry)
        }

        let writtenJSON = try String(contentsOf: claudeURL, encoding: .utf8)
        let objectContents = writtenJSON.drop(while: { $0.isWhitespace || $0 == "{" })
        #expect(objectContents.hasPrefix("\"mcpServers\""))
        let mcpRange = writtenJSON.range(of: "\"mcpServers\"")
        let themeRange = writtenJSON.range(of: "\"theme\"")
        #expect(mcpRange != nil)
        #expect(themeRange != nil)
        #expect(mcpRange!.lowerBound < themeRange!.lowerBound)
    }

    @Test(arguments: [false, true])
    func repeatedSyncWritesIdenticalJSONAndPreservesValues(directToggle: Bool) throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let claudeURL = tempRoot.appendingPathComponent("claude_desktop_config.json")
        let original = #"""
        {
          "theme": "dark",
          "autoUpdates": false,
          "quoted\"key\\with\nnewline": {
            "z": [null, true, 12.5, "line 1\nline 2", "Unicode: café"],
            "a": {"z": "https://example.com/mcp", "a": "first"}
          },
          "mcpServers": {}
        }
        """#
        try original.write(to: claudeURL, atomically: true, encoding: .utf8)
        let store = ClaudeConfigStore(
            configURLProvider: { claudeURL },
            backupService: BackupService(backupsDirectoryURL: tempRoot.appendingPathComponent("backups"))
        )
        let registry = ServerRegistry(servers: [
            ManagedServer(name: "Second", config: MCPServerConfig(command: "node", env: ["Z": "last", "A": "first"])),
            ManagedServer(name: "First", config: MCPServerConfig(command: "npx"))
        ])
        try store.syncEnabledServers(from: registry)
        let firstWrite = try Data(contentsOf: claudeURL)
        let expectedValues = try store.loadConfig().values
        let originalValues = try JSONDecoder().decode(ClaudeDesktopConfig.self, from: Data(original.utf8)).values
        for (key, value) in originalValues where key != "mcpServers" {
            #expect(expectedValues[key] == value)
        }

        for _ in 0..<10 {
            if directToggle {
                try store.syncServer(registry.servers[0])
            } else {
                try store.syncEnabledServers(from: registry)
            }
            #expect(try Data(contentsOf: claudeURL) == firstWrite)
            #expect(try store.loadConfig().values == expectedValues)
        }
    }
}
