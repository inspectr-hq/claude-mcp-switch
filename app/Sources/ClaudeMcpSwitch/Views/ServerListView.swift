import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP Servers")
                        .font(.title2)
                    Text("Current registry stored locally and synced into Claude Desktop on demand.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Import from Claude Desktop") {
                    coordinator.importFromClaudeConfig()
                }
                Button("Sync to Claude Desktop") {
                    coordinator.syncToClaudeConfig()
                }
                .buttonStyle(.borderedProminent)
            }

            List {
                ForEach(coordinator.registry.servers) { server in
                    HStack(spacing: 12) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { server.enabled },
                                set: { coordinator.setEnabled($0, for: server.id) }
                            )
                        )
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.headline)
                            Text(server.config.command)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(server.updatedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if coordinator.registry.servers.isEmpty {
                    ContentUnavailableView(
                        "No Managed Servers",
                        systemImage: "server.rack",
                        description: Text("Import from Claude Desktop or add registry data in a later implementation pass.")
                    )
                }
            }

            if let statusMessage = coordinator.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
