import SwiftUI

@main
struct ClaudeMcpSwitchApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(coordinator)
        } label: {
            Image(systemName: "server.rack")
        }
        .menuBarExtraStyle(.window)
    }
}
