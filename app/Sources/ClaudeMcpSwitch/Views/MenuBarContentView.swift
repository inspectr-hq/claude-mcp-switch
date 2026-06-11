import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                if let logoImage {
                    Image(nsImage: logoImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                }

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            if coordinator.registry.servers.isEmpty {
                Text("No servers in registry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(coordinator.registry.servers) { server in
                    serverRow(server)
                }
            }

            Divider()
            menuAction("Manage MCP servers") {
                WindowManager.shared.showManager(coordinator: coordinator)
            }
            Divider()
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

    @ViewBuilder
    private func serverRow(_ server: ManagedServer) -> some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { server.enabled },
                    set: { coordinator.setEnabled($0, for: server.id) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .lineLimit(1)
                Text(server.config.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var logoImage: NSImage? {
        guard let url = resourceBundle.url(forResource: "ClaudeLogo", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var resourceBundle: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return Bundle.main
#endif
    }
}
