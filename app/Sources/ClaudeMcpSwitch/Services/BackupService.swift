import Foundation

struct BackupService {
    let backupsDirectoryURL: URL
    let fileManager: FileManager
    let now: () -> Date

    init(
        backupsDirectoryURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.backupsDirectoryURL = backupsDirectoryURL
        self.fileManager = fileManager
        self.now = now
    }

    func createBackupIfNeeded(sourceURL: URL, prefix: String) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }

        try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(prefix)_\(formatter.string(from: now())).json"
        let destinationURL = backupsDirectoryURL.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}
