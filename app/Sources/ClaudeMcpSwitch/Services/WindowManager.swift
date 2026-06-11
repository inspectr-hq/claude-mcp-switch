import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var managerWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var syncApprovalWindow: NSWindow?
    private var managerDelegate: NSWindowDelegate?
    private var settingsDelegate: NSWindowDelegate?
    private var syncApprovalDelegate: NSWindowDelegate?

    private init() {}

    private var hasOpenWindows: Bool {
        [managerWindow, settingsWindow, syncApprovalWindow].contains { $0 != nil }
    }

    private func updateActivationPolicy() {
        NSApp.setActivationPolicy(activationPolicy(hasOpenWindows: hasOpenWindows))
    }

    func showManager(coordinator: AppCoordinator) {
        updateActivationPolicy()
        if let window = managerWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ServerListView().environmentObject(coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MCP Servers"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        let delegate = WindowStateDelegate { [weak self] in
            self?.managerWindow = nil
            self?.managerDelegate = nil
            self?.updateActivationPolicy()
        }
        managerDelegate = delegate
        window.delegate = delegate
        managerWindow = window
        updateActivationPolicy()
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(coordinator: AppCoordinator) {
        updateActivationPolicy()
        if let window = settingsWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView().environmentObject(coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: 600, height: 620)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        let delegate = WindowStateDelegate(onClose: { [weak self] in
            self?.settingsWindow = nil
            self?.settingsDelegate = nil
            self?.updateActivationPolicy()
        }, preserveTopOnResize: true)
        settingsDelegate = delegate
        window.delegate = delegate
        settingsWindow = window
        updateActivationPolicy()
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSyncApproval(coordinator: AppCoordinator) {
        guard coordinator.syncPreview != nil || coordinator.syncRemovalWarning != nil else {
            closeSyncApproval()
            return
        }

        updateActivationPolicy()

        let view = SyncApprovalWindowView(
            onClose: { [weak self] in
                self?.closeSyncApproval()
            }
        )
        .environmentObject(coordinator)

        if let window = syncApprovalWindow {
            window.contentView = NSHostingView(rootView: view)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Approve Sync"
        window.minSize = NSSize(width: 560, height: 280)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        let delegate = WindowStateDelegate { [weak self, weak coordinator] in
            coordinator?.cancelSyncToClaudeConfig()
            self?.syncApprovalWindow = nil
            self?.syncApprovalDelegate = nil
            self?.updateActivationPolicy()
        }
        syncApprovalDelegate = delegate
        window.delegate = delegate
        syncApprovalWindow = window
        updateActivationPolicy()
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSyncApproval() {
        syncApprovalWindow?.close()
        syncApprovalWindow = nil
        syncApprovalDelegate = nil
        updateActivationPolicy()
    }
}

func activationPolicy(hasOpenWindows: Bool) -> NSApplication.ActivationPolicy {
    hasOpenWindows ? .regular : .accessory
}

private func centerHorizontally(_ window: NSWindow, topEdge: CGFloat? = nil) {
    let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    window.setFrameOrigin(
        windowCenteredOrigin(
            frame: window.frame,
            visibleFrame: visibleFrame,
            topEdge: topEdge
        )
    )
}

private final class WindowStateDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private let preserveTopOnResize: Bool
    private var topEdgeBeforeResize: CGFloat?

    init(onClose: @escaping () -> Void, preserveTopOnResize: Bool = false) {
        self.onClose = onClose
        self.preserveTopOnResize = preserveTopOnResize
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        guard preserveTopOnResize else { return frameSize }
        topEdgeBeforeResize = window.frame.maxY
        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard preserveTopOnResize else { return }
        centerHorizontally(window, topEdge: topEdgeBeforeResize)
    }
}

func windowCenteredOrigin(frame: NSRect, visibleFrame: NSRect, topEdge: CGFloat? = nil) -> CGPoint {
    let top = topEdge ?? frame.maxY
    return CGPoint(
        x: visibleFrame.midX - (frame.width / 2),
        y: top - frame.height
    )
}
