import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude MCP Switch")
                    .font(.headline)
                Text("\(coordinator.registry.servers.count) servers in registry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let statusMessage = coordinator.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
            menuAction("Open Manager") {
                WindowManager.shared.showManager(coordinator: coordinator)
            }
            menuAction("Sync to Claude Desktop") {
                coordinator.syncToClaudeConfig()
            }
            menuAction("Import from Claude Desktop") {
                coordinator.importFromClaudeConfig()
            }
            Divider()
            menuAction("Settings…") {
                WindowManager.shared.showSettings(coordinator: coordinator)
            }
            Divider()
            menuAction("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private func menuAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
