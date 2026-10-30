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

    private var applicationSupportBaseURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? homeDirectoryURL.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    var appSupportDirectoryURL: URL {
        applicationSupportBaseURL.appendingPathComponent("com.inspectr.ClaudeMcpSwitch", isDirectory: true)
    }

    var legacyAppSupportDirectoryURL: URL {
        applicationSupportBaseURL.appendingPathComponent("com. .ClaudeMcpSwitch", isDirectory: true)
    }

    /// Returns the preserved legacy data location when recovery or archiving occurred.
    func migrateLegacyStorageIfNeeded() throws -> URL? {
        let legacy = legacyAppSupportDirectoryURL
        let legacyExists = fileManager.fileExists(atPath: legacy.path)
        let destination = appSupportDirectoryURL
        if legacyExists && !fileManager.fileExists(atPath: destination.path) {
            // A rename keeps the registry, backups, and file permissions together.
            try fileManager.moveItem(at: legacy, to: destination)
            return nil
        }

        let archives = try pendingLegacyArchives()
        let source = fileManager.fileExists(atPath: legacy.appendingPathComponent("servers.json").path)
            ? legacy : archives.first
        if let source {
            // Validate before replacing a working current registry.
            try validateRegistry(in: source)

            // Older archives must not be restored on a later launch.
            for archive in archives where archive != source {
                try fileManager.moveItem(
                    at: archive.appendingPathComponent("servers.json"),
                    to: unusedURL(archive.appendingPathComponent("servers-before-migration.json"))
                )
            }
            try restoreLegacyRegistry(from: source)
        }

        guard legacyExists else { return source }
        try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        let archive = unusedURL(backupsDirectoryURL.appendingPathComponent("legacy", isDirectory: true))
        try fileManager.moveItem(at: legacy, to: archive)
        return archive
    }

    func legacyStorageDirectoryForRecovery() -> URL? {
        let candidates = [legacyAppSupportDirectoryURL] + ((try? pendingLegacyArchives()) ?? [])
        for directory in candidates {
            guard fileManager.fileExists(atPath: directory.appendingPathComponent("servers.json").path) else { continue }
            if (try? validateRegistry(in: directory)) != nil {
                return directory
            }
        }
        return nil
    }

    private func validateRegistry(in directory: URL) throws {
        _ = try RegistryStore(
            registryURL: directory.appendingPathComponent("servers.json"),
            backupsDirectoryURL: directory.appendingPathComponent("backups"),
            fileManager: fileManager
        ).loadRegistry()
    }

    private func restoreLegacyRegistry(from directory: URL) throws {
        let source = directory.appendingPathComponent("servers.json")
        let original = directory.appendingPathComponent("servers-before-migration.json")
        if !fileManager.fileExists(atPath: original.path) {
            try copyAtomically(from: source, to: original)
        }

        if fileManager.fileExists(atPath: registryURL.path) {
            try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
            let currentBackup = unusedURL(backupsDirectoryURL.appendingPathComponent("servers-before-migration.json"))
            try copyAtomically(from: registryURL, to: currentBackup)
            _ = try fileManager.replaceItemAt(registryURL, withItemAt: source, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: source, to: registryURL)
        }
        // Consuming source servers.json makes recovery one-time, even when the
        // subsequent directory archive fails. The snapshot above stays available.
    }

    private func pendingLegacyArchives() throws -> [URL] {
        guard fileManager.fileExists(atPath: backupsDirectoryURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: backupsDirectoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        let candidates = directories.filter {
            ($0.lastPathComponent == "legacy" || $0.lastPathComponent.hasPrefix("legacy-"))
                && fileManager.fileExists(atPath: $0.appendingPathComponent("servers.json").path)
        }
        let datedDirectories = try candidates.map { directory -> (directory: URL, modified: Date) in
            let attributes = try fileManager.attributesOfItem(atPath: directory.appendingPathComponent("servers.json").path)
            let modified = attributes[.modificationDate] as? Date ?? Date.distantPast
            return (directory, modified)
        }
        return datedDirectories.sorted {
            $0.modified == $1.modified ? $0.directory.path < $1.directory.path : $0.modified > $1.modified
        }
        .map(\.directory)
    }

    private func copyAtomically(from source: URL, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".migration-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private func unusedURL(_ proposed: URL) -> URL {
        var candidate = proposed
        while fileManager.fileExists(atPath: candidate.path) {
            let name = proposed.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString
            candidate = proposed.deletingLastPathComponent().appendingPathComponent(name)
            if !proposed.pathExtension.isEmpty {
                candidate.appendPathExtension(proposed.pathExtension)
            }
        }
        return candidate
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
