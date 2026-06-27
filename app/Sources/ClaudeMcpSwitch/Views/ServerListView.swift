import AppKit
import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var editingServer: ManagedServer?
    @State private var deletingServer: ManagedServer?

    var body: some View {
        content
            .sheet(item: $editingServer) { server in
                ServerEditorSheet(server: server) { updatedServer in
                    coordinator.updateServer(updatedServer)
                }
            }
            .alert(
                deleteAlertTitle,
                isPresented: deleteAlertIsPresented,
                presenting: deletingServer,
                actions: deleteAlertActions,
                message: deleteAlertMessage
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            serverList

            if let statusMessage = coordinator.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MCP Servers")
                    .font(.title2)
                Text("Your MCP Servers are stored locally and synced into Claude Desktop on demand.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Import from Claude Desktop") {
                coordinator.importFromClaudeConfig()
            }
            Button("Sync to Claude Desktop") {
                coordinator.requestSyncToClaudeConfig()
                WindowManager.shared.showSyncApproval(coordinator: coordinator)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var serverList: some View {
        List {
            ForEach(coordinator.registry.servers) { server in
                ServerManagerRow(
                    server: server,
                    onToggle: { coordinator.setEnabled($0, for: server.id) },
                    onEdit: { editingServer = server },
                    onDuplicate: {
                        if let duplicate = coordinator.duplicateServer(server.id) {
                            editingServer = duplicate
                        }
                    },
                    onDelete: { deletingServer = server }
                )
            }
        }
        .overlay {
            if coordinator.registry.servers.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No MCP Servers")
            } icon: {
                Image(systemName: "server.rack")
                    .rotationEffect(.degrees(180))
            }
        } description: {
            Text("Import from Claude Desktop or add MCP Servers in a later implementation pass.")
        }
    }

    private var deleteAlertIsPresented: Binding<Bool> {
        Binding(
            get: { deletingServer != nil },
            set: { isPresented in
                if !isPresented {
                    deletingServer = nil
                }
            }
        )
    }

    private var deleteAlertTitle: String {
        if let server = deletingServer {
            return "Delete \(server.name)?"
        }
        return ""
    }

    @ViewBuilder
    private func deleteAlertActions(server: ManagedServer) -> some View {
        Button("Cancel", role: .cancel) {
            deletingServer = nil
        }
        Button("Delete", role: .destructive) {
            coordinator.deleteServer(server.id)
            deletingServer = nil
        }
    }

    @ViewBuilder
    private func deleteAlertMessage(server: ManagedServer) -> some View {
        Text("This removes the MCP Server from Claude MCP Switch. It will no longer be available for sync unless you import or add it again.")
    }
}

private struct ServerManagerRow: View {
    let server: ManagedServer
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { server.enabled },
                    set: onToggle
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

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

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                Button("Duplicate", action: onDuplicate)
                Button("Delete", action: onDelete)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ManagedServer
    @State private var commandArguments: [EditableArgument]
    @State private var environmentEntries: [EditableEnvironmentEntry]
    @State private var validationMessage: String?
    @State private var snippetCopyMessage: String?

    let onSave: (ManagedServer) -> Void

    init(server: ManagedServer, onSave: @escaping (ManagedServer) -> Void) {
        _draft = State(initialValue: server)
        _commandArguments = State(
            initialValue: server.config.args.map { EditableArgument(value: $0) }
        )
        _environmentEntries = State(
            initialValue: server.config.env
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { EditableEnvironmentEntry(key: $0.key, value: $0.value) }
        )
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Edit MCP Server")
                            .font(.title2)
                        Text("Update one saved MCP Server in Claude MCP Switch.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("General")
                                    .font(.headline)
                                Text("Basic server identity and activation state.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            labeledRow("Name") {
                                TextField("Server name", text: $draft.name)
                                    .textFieldStyle(.roundedBorder)
                            }

                            labeledRow("Command") {
                                TextField("Executable command", text: $draft.config.command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                            }

                            labeledRow("Enabled") {
                                Toggle("", isOn: $draft.enabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        EmptyView()
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Arguments")
                                        .font(.headline)
                                    Text("Edit each command parameter separately.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Add Argument") {
                                    commandArguments.append(EditableArgument())
                                }
                            }

                            if commandArguments.isEmpty {
                                emptySectionRow("No arguments configured")
                            } else {
                                ForEach(Array($commandArguments.enumerated()), id: \.element.id) { index, $argument in
                                    HStack(spacing: 10) {
                                        Text("\(index + 1).")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, alignment: .trailing)

                                        TextField("Argument", text: $argument.value)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body.monospaced())

                                        Button {
                                            removeArgument(argument.id)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        EmptyView()
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Environment Variables")
                                        .font(.headline)
                                    Text("Set key/value pairs individually.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Add Variable") {
                                    environmentEntries.append(EditableEnvironmentEntry())
                                }
                            }

                            if environmentEntries.isEmpty {
                                emptySectionRow("No environment variables configured")
                            } else {
                                HStack(spacing: 10) {
                                    Text("Key")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Value")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Color.clear.frame(width: 18)
                                }

                                ForEach($environmentEntries) { $entry in
                                    HStack(spacing: 10) {
                                        TextField("KEY", text: $entry.key)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body.monospaced())

                                        TextField("VALUE", text: $entry.value)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body.monospaced())

                                        Button {
                                            removeEnvironmentEntry(entry.id)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        EmptyView()
                    }

                    GroupBox("Notes") {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 100)
                            .padding(.top, 8)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Claude Desktop JSON")
                                        .font(.headline)
                                    Text("Copy a ready-to-paste server snippet for claude_desktop_config.json.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Copy JSON") {
                                    copyJSONSnippet()
                                }
                                .buttonStyle(.bordered)
                            }

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.08))

                                ScrollView {
                                    Text(claudeDesktopJSONSnippet)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(minHeight: 120)

                            if let snippetCopyMessage {
                                Text(snippetCopyMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        EmptyView()
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(width: 640, height: 840)
    }

    @ViewBuilder
    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func emptySectionRow(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func save() {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = draft.config.command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationMessage = "Server name is required."
            return
        }

        guard !trimmedCommand.isEmpty else {
            validationMessage = "Command is required."
            return
        }

        do {
            draft.name = trimmedName
            draft.config.command = trimmedCommand
            draft.config.args = parseArgs(commandArguments)
            draft.config.env = try parseEnvironment(environmentEntries)
            onSave(draft)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func parseArgs(_ arguments: [EditableArgument]) -> [String] {
        arguments
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseEnvironment(_ entries: [EditableEnvironmentEntry]) throws -> [String: String] {
        var values: [String: String] = [:]

        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !(key.isEmpty && value.isEmpty) else {
                continue
            }

            guard !key.isEmpty else {
                throw ServerEditorError.invalidEnvironmentKey
            }

            values[key] = value
        }

        return values
    }

    private func removeArgument(_ id: UUID) {
        commandArguments.removeAll { $0.id == id }
    }

    private func removeEnvironmentEntry(_ id: UUID) {
        environmentEntries.removeAll { $0.id == id }
    }

    private var claudeDesktopJSONSnippet: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = draft.config.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverName = trimmedName.isEmpty ? "server-name" : trimmedName
        let config = MCPServerConfig(
            command: trimmedCommand.isEmpty ? draft.config.command : trimmedCommand,
            args: parseArgs(commandArguments),
            env: (try? parseEnvironment(environmentEntries)) ?? draft.config.env
        )

        let payload = ClaudeDesktopSnippetPayload(mcpServers: [serverName: config])

        guard
            let data = try? encoder.encode(payload),
            let snippet = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return snippet
    }

    private func copyJSONSnippet() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(claudeDesktopJSONSnippet, forType: .string)
        snippetCopyMessage = "Copied to clipboard."
    }
}

private struct EditableArgument: Identifiable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String = "") {
        self.id = id
        self.value = value
    }
}

private struct EditableEnvironmentEntry: Identifiable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

private enum ServerEditorError: LocalizedError {
    case invalidEnvironmentKey

    var errorDescription: String? {
        switch self {
        case .invalidEnvironmentKey:
            return "Environment variable keys cannot be empty."
        }
    }
}

private struct ClaudeDesktopSnippetPayload: Codable {
    var mcpServers: [String: MCPServerConfig]
}

struct SyncConfirmationSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let onClose: (() -> Void)?

    let preview: SyncPreview

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review Claude Desktop Changes")
                            .font(.title2)
                        Text("Claude MCP Switch is about to update the MCP Servers in Claude Desktop.")
                            .foregroundStyle(.secondary)
                        Text(preview.configPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Summary")
                                .font(.headline)

                            HStack(spacing: 16) {
                                summaryPill("\(preview.currentCount)", label: "Current")
                                summaryPill("\(preview.desiredCount)", label: "After Sync")
                                summaryPill("+\(preview.additions.count)", label: "Add")
                                summaryPill("~\(preview.updates.count)", label: "Update")
                                summaryPill("-\(preview.removals.count)", label: "Remove")
                            }

                            if preview.unchangedCount > 0 {
                                Text("\(preview.unchangedCount) server configurations will stay unchanged.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        EmptyView()
                    }

                    if !preview.additions.isEmpty {
                        syncChangeSection(
                            title: "Additions",
                            subtitle: "These MCP Servers are enabled in Claude MCP Switch and will be written into Claude Desktop.",
                            changes: preview.additions,
                            style: .addition
                        )
                    }

                    if !preview.updates.isEmpty {
                        syncChangeSection(
                            title: "Updates",
                            subtitle: "These existing Claude Desktop entries will be replaced with the Claude MCP Switch version.",
                            changes: preview.updates,
                            style: .update
                        )
                    }

                    if !preview.removals.isEmpty {
                        syncChangeSection(
                            title: "Only in Claude Desktop",
                            subtitle: "These MCP Servers exist in Claude Desktop but not in the enabled Claude MCP Switch list. They will be removed on sync.",
                            changes: preview.removals,
                            style: .removal
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                Text("This only updates MCP Servers. Other Claude Desktop keys stay intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    coordinator.cancelSyncToClaudeConfig()
                    onClose?()
                }

                Button("Approve Sync") {
                    coordinator.confirmSyncToClaudeConfig()
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(width: 720)
        .frame(minHeight: 360, idealHeight: preferredHeight, maxHeight: 720, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func syncChangeSection(
        title: String,
        subtitle: String,
        changes: [SyncPreviewChange],
        style: SyncChangeStyle
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(change.name)
                                .font(.headline)
                            Spacer()
                            Text(style.badgeText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(style.tint)
                        }

                        switch style {
                        case .addition:
                            if let desiredConfig = change.desiredConfig {
                                configCard("Will Add", config: desiredConfig)
                            }
                        case .update:
                            if let currentConfig = change.currentConfig {
                                configCard("Current", config: currentConfig)
                            }
                            if let desiredConfig = change.desiredConfig {
                                configCard("New", config: desiredConfig)
                            }
                        case .removal:
                            if let currentConfig = change.currentConfig {
                                configCard("Will Remove", config: currentConfig)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
        } label: {
            EmptyView()
        }
    }

    @ViewBuilder
    private func configCard(_ title: String, config: MCPServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(config.command)
                .font(.callout.monospaced())

            if !config.args.isEmpty {
                Text("Args: \(config.args.joined(separator: " "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            if !config.env.isEmpty {
                Text("Env: \(config.env.keys.sorted().joined(separator: ", "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func summaryPill(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var preferredHeight: CGFloat {
        let totalChanges = preview.additions.count + preview.updates.count + preview.removals.count
        let estimatedHeight = CGFloat(totalChanges) * 110
        return min(max(420, 250 + estimatedHeight), 720)
    }
}

struct SyncRemovalWarningSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let onClose: (() -> Void)?

    let warning: SyncRemovalWarning

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(warning.title)
                    .font(.title2)

                Text(warning.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Only in Claude Desktop")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(warning.removals, id: \.self) { serverName in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.square")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(serverName)
                                            .textSelection(.enabled)
                                        Text("Will be removed from Claude Desktop on sync")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 80, idealHeight: checklistIdealHeight, maxHeight: checklistMaxHeight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    coordinator.cancelSyncToClaudeConfig()
                    onClose?()
                }

                Button("Approve Sync") {
                    coordinator.confirmSyncToClaudeConfig()
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.bar)
        }
        .frame(width: 600)
        .frame(minHeight: 280, idealHeight: preferredHeight, maxHeight: 520)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var checklistHeight: CGFloat {
        CGFloat(warning.removals.count) * 42
    }

    private var checklistIdealHeight: CGFloat {
        max(80, checklistHeight)
    }

    private var checklistMaxHeight: CGFloat {
        min(max(80, checklistHeight), 220)
    }

    private var preferredHeight: CGFloat {
        min(max(280, 170 + checklistIdealHeight), 520)
    }
}

struct SyncApprovalWindowView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    let onClose: () -> Void

    var body: some View {
        Group {
            if let preview = coordinator.syncPreview {
                SyncConfirmationSheet(onClose: onClose, preview: preview)
            } else if let warning = coordinator.syncRemovalWarning {
                SyncRemovalWarningSheet(onClose: onClose, warning: warning)
            } else {
                VStack(spacing: 16) {
                    Text("No sync approval required.")
                        .foregroundStyle(.secondary)

                    Button("Close") {
                        onClose()
                    }
                }
                .frame(width: 420, height: 180)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum SyncChangeStyle {
    case addition
    case update
    case removal

    var badgeText: String {
        switch self {
        case .addition:
            return "ADD"
        case .update:
            return "UPDATE"
        case .removal:
            return "REMOVE"
        }
    }

    var tint: Color {
        switch self {
        case .addition:
            return .green
        case .update:
            return .orange
        case .removal:
            return .red
        }
    }
}
