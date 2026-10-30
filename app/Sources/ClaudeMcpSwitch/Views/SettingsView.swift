import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var customPathEnabled = false
    private let appInfo = AppInstallationInfo()

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: appInfo.versionDescription)

                LabeledContent("GitHub") {
                    Link("inspectr-hq/claude-mcp-switch", destination: AppInstallationInfo.repositoryURL)
                }

                LabeledContent("Installation", value: appInfo.installationDescription)

                LabeledContent("Location") {
                    Text(appInfo.appURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Claude Desktop Config") {
                Toggle("Use custom config path", isOn: $customPathEnabled)

                TextField(
                    "Path",
                    text: Binding(
                        get: { coordinator.settings.claudeConfigPathOverride ?? "" },
                        set: { newValue in
                            coordinator.settings.claudeConfigPathOverride = newValue.isEmpty ? nil : newValue
                            coordinator.saveSettings()
                        }
                    )
                )
                .disabled(!customPathEnabled)

                Text(coordinator.effectiveClaudeConfigPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync Behavior") {
                Toggle(
                    "Write toggle changes directly to Claude Desktop",
                    isOn: Binding(
                        get: { coordinator.settings.directToggleSyncToClaudeConfig },
                        set: { newValue in
                            coordinator.settings.directToggleSyncToClaudeConfig = newValue
                            coordinator.saveSettings()
                        }
                    )
                )

                Text("When enabled, turning one MCP Server on or off updates only that single item in Claude Desktop's mcpServers list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("MCP Servers Storage") {
                Text(coordinator.registryStore.registryURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
                Text(coordinator.registryStore.backupsDirectoryURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Status") {
                Text(coordinator.statusMessage ?? "No recent operation")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            customPathEnabled = coordinator.settings.claudeConfigPathOverride != nil
        }
        .onChange(of: customPathEnabled) { _, isEnabled in
            if !isEnabled {
                coordinator.settings.claudeConfigPathOverride = nil
                coordinator.saveSettings()
            } else if coordinator.settings.claudeConfigPathOverride == nil {
                coordinator.settings.claudeConfigPathOverride = coordinator.effectiveClaudeConfigPath
                coordinator.saveSettings()
            }
        }
    }
}
