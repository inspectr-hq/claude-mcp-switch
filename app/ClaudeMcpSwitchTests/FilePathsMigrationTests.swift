import Foundation
import Testing
@testable import ClaudeMcpSwitch

@MainActor
struct FilePathsMigrationTests {
    @Test func storagePathMatchesBundleIdentifier() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        #expect(fixture.paths.appSupportDirectoryURL == fixture.correctedURL)
        #expect(fixture.paths.registryURL == fixture.correctedURL.appendingPathComponent("servers.json"))
    }

    @Test func firstLaunchMigratesRegistryOrderAndAllBackups() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registry = fixture.sampleRegistry
        try fixture.writeRegistry(registry, in: fixture.legacyURL)
        let original = try Data(contentsOf: fixture.legacyURL.appendingPathComponent("servers.json"))
        try fixture.writeBackup("registry backup", name: "servers_old.json")
        try fixture.writeBackup("Claude config backup", name: "claude_desktop_config_old.json")

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == registry)
        #expect(coordinator.registryStore.registryURL == fixture.correctedURL.appendingPathComponent("servers.json"))
        #expect(try Data(contentsOf: coordinator.registryStore.registryURL) == original)
        #expect(try String(contentsOf: fixture.correctedURL.appendingPathComponent("backups/servers_old.json")) == "registry backup")
        #expect(try String(contentsOf: fixture.correctedURL.appendingPathComponent("backups/claude_desktop_config_old.json")) == "Claude config backup")
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyURL.path))
        #expect(fixture.makeCoordinator().registry == registry)
    }

    @Test func existingCurrentRegistryIsBackedUpAndLegacyListIsRestoredAsIs() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.writeRegistry(fixture.sampleRegistry, in: fixture.legacyURL)
        try fixture.writeBackup("old backup", name: "same.json")
        let current = ServerRegistry(servers: [ManagedServer(name: "Current", config: MCPServerConfig(command: "uv"))])
        try fixture.writeRegistry(current, in: fixture.correctedURL)
        let currentData = try Data(contentsOf: fixture.correctedURL.appendingPathComponent("servers.json"))
        let backups = fixture.correctedURL.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try "current backup".write(to: backups.appendingPathComponent("same.json"), atomically: true, encoding: .utf8)
        // An existing archive must also survive migration.
        let priorArchive = backups.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: priorArchive, withIntermediateDirectories: true)
        try "prior archive".write(to: priorArchive.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(try Data(contentsOf: backups.appendingPathComponent("servers-before-migration.json")) == currentData)
        #expect(try String(contentsOf: backups.appendingPathComponent("same.json")) == "current backup")
        #expect(try String(contentsOf: priorArchive.appendingPathComponent("keep.txt")) == "prior archive")
        let archives = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("legacy-") }
        let archive = try #require(archives.first)
        #expect(archives.count == 1)
        #expect(try RegistryStore(registryURL: archive.appendingPathComponent("servers-before-migration.json"), backupsDirectoryURL: archive.appendingPathComponent("backups")).loadRegistry() == fixture.sampleRegistry)
        #expect(try String(contentsOf: archive.appendingPathComponent("backups/same.json")) == "old backup")
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyURL.path))

        _ = fixture.makeCoordinator()
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).count == 4)
    }

    @Test func existingDirectoryWithoutRegistryRecoversLegacyServers() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.writeRegistry(fixture.sampleRegistry, in: fixture.legacyURL)
        try fixture.writeBackup("old backup", name: "servers_old.json")
        try FileManager.default.createDirectory(at: fixture.correctedURL, withIntermediateDirectories: true)

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(try String(contentsOf: fixture.correctedURL.appendingPathComponent("backups/legacy/backups/servers_old.json")) == "old backup")
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyURL.path))
    }

    @Test(arguments: [false, true])
    func migrationFailureKeepsUsingLegacyData(correctedDirectoryExists: Bool) throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.writeRegistry(fixture.sampleRegistry, in: fixture.legacyURL)
        try fixture.writeBackup("old backup", name: "servers_old.json")
        if correctedDirectoryExists {
            try FileManager.default.createDirectory(at: fixture.correctedURL, withIntermediateDirectories: true)
        }
        fixture.fileManager.failMoves = true

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(coordinator.registryStore.registryURL == fixture.legacyURL.appendingPathComponent("servers.json"))
        #expect(coordinator.registryStore.backupsDirectoryURL == fixture.legacyURL.appendingPathComponent("backups"))
        #expect(coordinator.statusMessage?.contains("migration failed") == true)
        #expect(try String(contentsOf: fixture.legacyURL.appendingPathComponent("backups/servers_old.json")) == "old backup")
        if correctedDirectoryExists {
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.correctedURL.path).isEmpty)
        }

        fixture.fileManager.failMoves = false
        #expect(fixture.makeCoordinator().registry == fixture.sampleRegistry)
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyURL.path))
    }

    @Test func freshInstallUsesCorrectedPathWithoutCreatingLegacyStorage() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let coordinator = fixture.makeCoordinator()
        #expect(coordinator.registry.servers.isEmpty)
        #expect(coordinator.registryStore.registryURL == fixture.correctedURL.appendingPathComponent("servers.json"))
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyURL.path))
        #expect(coordinator.statusMessage == nil)
    }

    @Test(arguments: [false, true])
    func archiveFailureKeepsCurrentRegistryAndLaterEdits(currentRegistryExists: Bool) throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.writeRegistry(fixture.sampleRegistry, in: fixture.legacyURL)
        try fixture.writeBackup("old backup", name: "servers_old.json")
        try FileManager.default.createDirectory(at: fixture.correctedURL, withIntermediateDirectories: true)
        let current = currentRegistryExists
            ? ServerRegistry(servers: [ManagedServer(name: "Current", config: MCPServerConfig(command: "uv"))])
            : fixture.sampleRegistry
        if currentRegistryExists {
            try fixture.writeRegistry(current, in: fixture.correctedURL)
        }
        fixture.fileManager.failingMoveSource = fixture.legacyURL

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(coordinator.registryStore.registryURL == fixture.correctedURL.appendingPathComponent("servers.json"))
        #expect(coordinator.statusMessage?.contains("migration failed") == true)
        coordinator.registry.servers[0].notes = "Edited after partial migration"
        coordinator.saveRegistry()

        fixture.fileManager.failingMoveSource = nil
        let reloaded = fixture.makeCoordinator()
        #expect(reloaded.registry.servers.map(\.id) == fixture.sampleRegistry.servers.map(\.id))
        #expect(reloaded.registry.servers[0].notes == "Edited after partial migration")
        #expect(try String(contentsOf: fixture.correctedURL.appendingPathComponent("backups/legacy/backups/servers_old.json")) == "old backup")
        #expect(!FileManager.default.fileExists(atPath: fixture.legacyURL.path))
    }

    @Test func alreadyArchivedRegistryIsRecoveredOnceAndCurrentCopyIsBackedUp() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archive = fixture.correctedURL.appendingPathComponent("backups/legacy")
        try fixture.writeRegistry(fixture.sampleRegistry, in: archive)
        let originalData = try Data(contentsOf: archive.appendingPathComponent("servers.json"))
        let current = ServerRegistry(servers: [ManagedServer(name: "Other", config: MCPServerConfig(command: "uv"))])
        try fixture.writeRegistry(current, in: fixture.correctedURL)
        let currentData = try Data(contentsOf: fixture.correctedURL.appendingPathComponent("servers.json"))

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(try Data(contentsOf: coordinator.registryStore.registryURL) == originalData)
        #expect(try Data(contentsOf: fixture.correctedURL.appendingPathComponent("backups/servers-before-migration.json")) == currentData)
        #expect(try Data(contentsOf: archive.appendingPathComponent("servers-before-migration.json")) == originalData)
        coordinator.registry.servers.removeLast()
        coordinator.registry.servers[0].notes = "Keep later edits"
        coordinator.saveRegistry()

        let reloaded = fixture.makeCoordinator()
        #expect(reloaded.registry.servers.count == 1)
        #expect(reloaded.registry.servers[0].notes == "Keep later edits")
    }

    @Test func multipleArchivesRecoverNewestRegistryWithoutRestoringOlderOnNextLaunch() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let newerArchive = fixture.correctedURL.appendingPathComponent("backups/legacy")
        let olderArchive = fixture.correctedURL.appendingPathComponent("backups/legacy-older")
        try fixture.writeRegistry(fixture.sampleRegistry, in: newerArchive)
        try fixture.writeRegistry(ServerRegistry(), in: olderArchive)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newerArchive.appendingPathComponent("servers.json").path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: olderArchive.appendingPathComponent("servers.json").path)

        #expect(fixture.makeCoordinator().registry == fixture.sampleRegistry)
        #expect(fixture.makeCoordinator().registry == fixture.sampleRegistry)
        #expect(FileManager.default.fileExists(atPath: olderArchive.appendingPathComponent("servers-before-migration.json").path))
    }

    @Test func archivedRegistryRemainsUsableAfterFailedRecoveryAndRetry() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archive = fixture.correctedURL.appendingPathComponent("backups/legacy")
        try fixture.writeRegistry(fixture.sampleRegistry, in: archive)
        fixture.fileManager.failMoves = true

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(coordinator.registryStore.registryURL.resolvingSymlinksInPath() == archive.appendingPathComponent("servers.json").resolvingSymlinksInPath())
        coordinator.registry.servers[0].notes = "Edited during recovery failure"
        coordinator.saveRegistry()
        fixture.fileManager.failMoves = false

        let reloaded = fixture.makeCoordinator()
        #expect(reloaded.registryStore.registryURL == fixture.correctedURL.appendingPathComponent("servers.json"))
        #expect(reloaded.registry.servers[0].notes == "Edited during recovery failure")
    }

    @Test func failedReplacementPreservesBothRegistriesAndRetries() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.writeRegistry(fixture.sampleRegistry, in: fixture.legacyURL)
        let current = ServerRegistry(servers: [ManagedServer(name: "Other", config: MCPServerConfig(command: "uv"))])
        try fixture.writeRegistry(current, in: fixture.correctedURL)
        let currentData = try Data(contentsOf: fixture.correctedURL.appendingPathComponent("servers.json"))
        fixture.fileManager.failReplacements = true

        let coordinator = fixture.makeCoordinator()

        #expect(try Data(contentsOf: fixture.correctedURL.appendingPathComponent("servers.json")) == currentData)
        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(coordinator.registryStore.registryURL == fixture.legacyURL.appendingPathComponent("servers.json"))
        #expect(FileManager.default.fileExists(atPath: fixture.legacyURL.appendingPathComponent("servers.json").path))
        #expect(coordinator.statusMessage?.contains("migration failed") == true)
        coordinator.registry.servers[0].notes = "Edited while replacement failed"
        coordinator.saveRegistry()
        fixture.fileManager.failReplacements = false
        let reloaded = fixture.makeCoordinator()
        #expect(reloaded.registry.servers.map(\.id) == fixture.sampleRegistry.servers.map(\.id))
        #expect(reloaded.registry.servers[0].notes == "Edited while replacement failed")
    }

    @Test func invalidLegacyRegistryDoesNotReplaceWorkingCurrentRegistry() throws {
        let fixture = try MigrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.writeRegistry(fixture.sampleRegistry, in: fixture.correctedURL)
        try FileManager.default.createDirectory(at: fixture.legacyURL, withIntermediateDirectories: true)
        try "invalid JSON".write(to: fixture.legacyURL.appendingPathComponent("servers.json"), atomically: true, encoding: .utf8)

        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.registry == fixture.sampleRegistry)
        #expect(coordinator.registryStore.registryURL == fixture.correctedURL.appendingPathComponent("servers.json"))
        #expect(coordinator.statusMessage?.contains("migration failed") == true)
        #expect(try String(contentsOf: fixture.legacyURL.appendingPathComponent("servers.json")) == "invalid JSON")
    }
}

@MainActor
private struct MigrationFixture {
    let root: URL
    let legacyURL: URL
    let correctedURL: URL
    let fileManager: MigrationFileManager
    let paths: FilePaths

    var sampleRegistry: ServerRegistry {
        ServerRegistry(servers: [
            ManagedServer(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                name: "Zulu", enabled: false,
                config: MCPServerConfig(command: "npx", args: ["server"], env: ["TOKEN": "sample"]),
                notes: "keep notes", createdAt: .distantPast, updatedAt: .distantPast
            ),
            ManagedServer(
                id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
                name: "Alpha", config: MCPServerConfig(command: "uv"),
                createdAt: .distantPast, updatedAt: .distantPast
            )
        ])
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        legacyURL = support.appendingPathComponent("com. .ClaudeMcpSwitch", isDirectory: true)
        correctedURL = support.appendingPathComponent("com.inspectr.ClaudeMcpSwitch", isDirectory: true)
        fileManager = MigrationFileManager(appSupportURL: support)
        paths = FilePaths(fileManager: fileManager, homeDirectoryURL: root)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func writeRegistry(_ registry: ServerRegistry, in directory: URL) throws {
        try RegistryStore(
            registryURL: directory.appendingPathComponent("servers.json"),
            backupsDirectoryURL: directory.appendingPathComponent("backups")
        ).saveRegistry(registry)
    }

    func writeBackup(_ contents: String, name: String) throws {
        let directory = legacyURL.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func makeCoordinator() -> AppCoordinator {
        AppCoordinator(
            paths: paths,
            settingsDefaults: UserDefaults(suiteName: "MigrationTests.\(UUID().uuidString)")!,
            claudeDesktopService: MigrationDesktopService()
        )
    }
}

private final class MigrationFileManager: FileManager {
    let appSupportURL: URL
    var failMoves = false
    var failingMoveSource: URL?
    var failReplacements = false

    init(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        directory == .applicationSupportDirectory ? [appSupportURL] : super.urls(for: directory, in: domainMask)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if failMoves || srcURL == failingMoveSource { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func replaceItem(
        at originalItemURL: URL, withItemAt newItemURL: URL,
        backupItemName: String?, options: ItemReplacementOptions = [],
        resultingItemURL resultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        if failReplacements { throw CocoaError(.fileWriteNoPermission) }
        try super.replaceItem(at: originalItemURL, withItemAt: newItemURL, backupItemName: backupItemName, options: options, resultingItemURL: resultingURL)
    }
}

@MainActor
private final class MigrationDesktopService: ClaudeDesktopServicing {
    var isRunning: Bool { false }
    func setRunningStateDidChangeHandler(_ handler: (@MainActor (Bool) -> Void)?) {}
    func restartClaudeDesktop() async throws {}
}
