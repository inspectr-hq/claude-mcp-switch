import Foundation

struct FilePaths {
    let fileManager: FileManager
    let homeDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
    }

    var appSupportDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? homeDirectoryURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("com. .ClaudeMcpSwitch", isDirectory: true)
    }

    var registryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("servers.json")
    }

    var backupsDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("backups", isDirectory: true)
    }

    var defaultClaudeConfigURL: URL {
        homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")
    }
}
