import Foundation
import Testing
@testable import ClaudeMcpSwitch

struct AppInstallationInfoTests {
    @Test(arguments: [
        ("1.2.3", "42", "1.2.3 (42)"),
        ("1.2.3", nil, "1.2.3"),
        (nil, "42", "Build 42"),
        (nil, nil, "Development build"),
        ("", "", "Development build")
    ])
    func versionDescriptionUsesBundleMetadata(version: String?, build: String?, expected: String) {
        let info = AppInstallationInfo(
            version: version,
            build: build,
            appURL: URL(fileURLWithPath: "/Applications/Claude MCP Switch.app"),
            caskroomURLs: []
        )
        #expect(info.versionDescription == expected)
    }

    @Test func homebrewDetectsCaskLinkToRunningApp() throws {
        let fixture = try InstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.createSymbolicLink(at: fixture.stagedApp, withDestinationURL: fixture.app)

        let info = AppInstallationInfo(appURL: fixture.app, caskroomURLs: [fixture.caskroom])

        #expect(info.installationDescription == "Homebrew")
        #expect(info.appURL == fixture.app)
    }

    @Test func separateManualCopyIsNotLabeledHomebrew() throws {
        let fixture = try InstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.createSymbolicLink(at: fixture.stagedApp, withDestinationURL: fixture.app)
        let manualCopy = fixture.root.appendingPathComponent("Downloads/Claude MCP Switch.app")
        try FileManager.default.createDirectory(at: manualCopy, withIntermediateDirectories: true)

        let info = AppInstallationInfo(appURL: manualCopy, caskroomURLs: [fixture.caskroom])

        #expect(info.installationDescription == "Manual")
    }

    @Test func missingOrStaleCaskIsManual() throws {
        let fixture = try InstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missing = fixture.root.appendingPathComponent("MissingCaskroom")
        try FileManager.default.createSymbolicLink(
            at: fixture.stagedApp,
            withDestinationURL: fixture.root.appendingPathComponent("Removed/Claude MCP Switch.app")
        )
        #expect(AppInstallationInfo(appURL: fixture.app, caskroomURLs: [missing, fixture.caskroom])
            .installationDescription == "Manual")
    }

    @Test func appRunningInsideCustomCaskroomIsHomebrew() throws {
        let fixture = try InstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.createDirectory(at: fixture.stagedApp, withIntermediateDirectories: true)

        #expect(AppInstallationInfo(appURL: fixture.stagedApp, caskroomURLs: [fixture.caskroom])
            .installationDescription == "Homebrew")
    }

    @Test func caskroomSearchIncludesCustomAndStandardPrefixes() {
        let roots = AppInstallationInfo.caskroomURLs(environment: [
            "HOMEBREW_CASKROOM": "/custom/casks",
            "HOMEBREW_PREFIX": "/custom/brew"
        ])
        #expect(roots.map(\.path) == [
            "/custom/casks", "/custom/brew/Caskroom", "/opt/homebrew/Caskroom", "/usr/local/Caskroom"
        ])
    }
}

private struct InstallationFixture {
    let root: URL
    let app: URL
    let caskroom: URL
    let stagedApp: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = root.appendingPathComponent("Applications/Claude MCP Switch.app")
        caskroom = root.appendingPathComponent("custom/Caskroom")
        stagedApp = caskroom.appendingPathComponent("claude-mcp-switch/1.2.3/Claude MCP Switch.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagedApp.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
