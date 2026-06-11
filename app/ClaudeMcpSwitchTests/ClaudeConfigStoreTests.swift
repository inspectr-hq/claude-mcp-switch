import Foundation
import Testing
@testable import ClaudeMcpSwitch

struct ClaudeConfigStoreTests {
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
}
