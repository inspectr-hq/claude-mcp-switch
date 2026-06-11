import AppKit
import SwiftUI

@main
struct ClaudeMcpSwitchApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(coordinator)
        } label: {
            Image(nsImage: rotatedMenuBarImage)
        }
        .menuBarExtraStyle(.window)
    }

    private var rotatedMenuBarImage: NSImage {
        let baseImage = NSImage(
            systemSymbolName: "server.rack",
            accessibilityDescription: "Claude MCP Switch"
        ) ?? NSImage()
        let imageSize = NSSize(width: 18, height: 18)
        let rotatedImage = NSImage(size: imageSize)

        rotatedImage.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            rotatedImage.unlockFocus()
            baseImage.isTemplate = true
            return baseImage
        }

        context.translateBy(x: imageSize.width / 2, y: imageSize.height / 2)
        context.rotate(by: .pi)
        context.translateBy(x: -imageSize.width / 2, y: -imageSize.height / 2)

        baseImage.draw(
            in: NSRect(origin: .zero, size: imageSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        rotatedImage.unlockFocus()
        rotatedImage.isTemplate = true

        return rotatedImage
    }
}
