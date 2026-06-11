import Foundation

protocol RegistryStoreProtocol {
    func loadRegistry() throws -> ServerRegistry
    func saveRegistry(_ registry: ServerRegistry) throws
}

struct RegistryStore: RegistryStoreProtocol {
    let registryURL: URL
    let backupsDirectoryURL: URL
    private let fileManager: FileManager
    private let backupService: BackupService

    init(
        registryURL: URL,
        backupsDirectoryURL: URL,
        fileManager: FileManager = .default,
        backupService: BackupService? = nil
    ) {
        self.registryURL = registryURL
        self.backupsDirectoryURL = backupsDirectoryURL
        self.fileManager = fileManager
        self.backupService = backupService ?? BackupService(backupsDirectoryURL: backupsDirectoryURL, fileManager: fileManager)
    }

    func loadRegistry() throws -> ServerRegistry {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return ServerRegistry()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: registryURL)
        return try decoder.decode(ServerRegistry.self, from: data)
    }

    func saveRegistry(_ registry: ServerRegistry) throws {
        try fileManager.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try backupService.createBackupIfNeeded(sourceURL: registryURL, prefix: "servers")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(registry)
        try data.write(to: registryURL, options: .atomic)
    }
}
