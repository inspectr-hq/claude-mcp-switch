import Foundation

struct AppInstallationInfo {
    static let repositoryURL = URL(string: "https://github.com/inspectr-hq/claude-mcp-switch")!

    let appURL: URL
    let versionDescription: String
    let installationDescription: String

    init(
        version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        build: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        appURL: URL = Bundle.main.bundleURL,
        caskroomURLs: [URL] = AppInstallationInfo.caskroomURLs(environment: ProcessInfo.processInfo.environment),
        fileManager: FileManager = .default
    ) {
        self.appURL = appURL

        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let build = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !version.isEmpty {
            versionDescription = build.isEmpty ? version : "\(version) (\(build))"
        } else {
            versionDescription = build.isEmpty ? "Development build" : "Build \(build)"
        }

        let resolvedApp = appURL.resolvingSymlinksInPath().standardizedFileURL
        let isHomebrew = caskroomURLs.contains { caskroom in
            let cask = caskroom.appendingPathComponent("claude-mcp-switch", isDirectory: true)
            let versions = (try? fileManager.contentsOfDirectory(
                at: cask,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []

            return versions.contains { versionDirectory in
                let stagedApp = versionDirectory.appendingPathComponent(resolvedApp.lastPathComponent)
                return fileManager.fileExists(atPath: stagedApp.path)
                    && stagedApp.resolvingSymlinksInPath().standardizedFileURL == resolvedApp
            }
        }
        installationDescription = isHomebrew ? "Homebrew" : "Manual"
    }

    static func caskroomURLs(environment: [String: String]) -> [URL] {
        var paths: [String] = []
        if let caskroom = environment["HOMEBREW_CASKROOM"], !caskroom.isEmpty {
            paths.append(caskroom)
        }
        if let prefix = environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            paths.append(prefix + "/Caskroom")
        }
        paths.append(contentsOf: ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"])
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
