import AppKit
import Foundation

@MainActor
protocol ClaudeDesktopServicing: AnyObject {
    var isRunning: Bool { get }
    func setRunningStateDidChangeHandler(_ handler: (@MainActor (Bool) -> Void)?)
    func restartClaudeDesktop() async throws
}

enum ClaudeDesktopServiceError: LocalizedError {
    case applicationNotFound
    case terminateFailed
    case relaunchTimedOut

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            return "Claude Desktop.app could not be found."
        case .terminateFailed:
            return "Claude Desktop could not be asked to quit."
        case .relaunchTimedOut:
            return "Claude Desktop did not quit in time for restart."
        }
    }
}

final class ClaudeDesktopService: ClaudeDesktopServicing {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private var observerTokens: [NSObjectProtocol] = []
    private var runningStateDidChangeHandler: (@MainActor (Bool) -> Void)?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.notificationCenter = workspace.notificationCenter
        startObservingWorkspace()
    }

    deinit {
        observerTokens.forEach(notificationCenter.removeObserver)
    }

    var isRunning: Bool {
        !runningApplications.isEmpty
    }

    func setRunningStateDidChangeHandler(_ handler: (@MainActor (Bool) -> Void)?) {
        runningStateDidChangeHandler = handler
    }

    func restartClaudeDesktop() async throws {
        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            throw ClaudeDesktopServiceError.applicationNotFound
        }

        if let runningApp = runningApplications.first {
            guard runningApp.terminate() else {
                throw ClaudeDesktopServiceError.terminateFailed
            }

            try await waitUntilNotRunning()
        }

        try await openApplication(at: applicationURL)
    }

    private func startObservingWorkspace() {
        let didLaunch = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleWorkspaceNotification(notification)
            }
        }

        let didTerminate = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleWorkspaceNotification(notification)
            }
        }

        observerTokens = [didLaunch, didTerminate]
    }

    private func handleWorkspaceNotification(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            application.bundleIdentifier == Self.bundleIdentifier
        else {
            return
        }

        let running = notification.name == NSWorkspace.didLaunchApplicationNotification
        Task { @MainActor [weak self] in
            self?.runningStateDidChangeHandler?(running)
        }
    }

    private var runningApplications: [NSRunningApplication] {
        workspace.runningApplications.filter { $0.bundleIdentifier == Self.bundleIdentifier }
    }

    private func waitUntilNotRunning(timeoutSeconds: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while isRunning {
            if Date() >= deadline {
                throw ClaudeDesktopServiceError.relaunchTimedOut
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func openApplication(at applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
