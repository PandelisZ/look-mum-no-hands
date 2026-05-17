import LMNHCore
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var model: ControlPanelModel
    @SceneStorage("control-panel.selected-pane") private var selectedPaneRawValue = RightPane.cursorOptions.rawValue

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    permissionCard
                    serverCard
                }
                .padding(24)
            }
            .frame(width: 360)
            .background(.regularMaterial)

            Divider()

            rightPane
        }
    }

    private var selectedPane: RightPane {
        RightPane(rawValue: selectedPaneRawValue) ?? .logs
    }

    private var selectedPaneBinding: Binding<RightPane> {
        Binding(
            get: { selectedPane },
            set: { selectedPaneRawValue = $0.rawValue }
        )
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Pane", selection: selectedPaneBinding) {
                ForEach(RightPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedPane {
            case .logs:
                logsPane
            case .cursorOptions:
                cursorOptionsPane
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Look Mum No Hands")
                .font(.largeTitle.weight(.bold))
            Text("Focusless macOS control with an animated virtual cursor.")
                .foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)
            PermissionRow(title: "Accessibility", state: model.permissionStatus.accessibility)
            PermissionRow(title: "Screen Recording", state: model.permissionStatus.screenCapture)
            HStack {
                Button("Accessibility Settings") { model.openAccessibilitySettings() }
                Button("Screen Recording") { model.openScreenRecordingSettings() }
            }
            .buttonStyle(.bordered)
            Text("Settings \(LMNHPaths.stateDirectory.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Process \(model.permissionStatus.processIdentifier)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.background.opacity(0.72)))
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCP Server")
                .font(.headline)
            HStack {
                Circle()
                    .fill(model.isMCPServerRunning ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(model.isMCPServerRunning ? "HTTP MCP server running" : "HTTP MCP server stopped")
                Spacer()
                Text("port \(model.mcpServerPort)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("HTTP endpoint")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.mcpServerURL)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Start HTTP") { model.startMCPServer() }
                    .disabled(model.isMCPServerRunning)
                Button("Stop HTTP") { model.stopMCPServer() }
                    .disabled(!model.isMCPServerRunning)
                Button("Copy URL") { model.copyMCPServerURL() }
            }
            .buttonStyle(.bordered)

            HStack {
                Button("Install Cursor") { model.installCursorPlugin() }
                Button("Install Codex") { model.installCodexPlugin() }
                Button("Install Claude") { model.installClaudePlugin() }
            }
            .buttonStyle(.bordered)

            Button("Install All Plugins") { model.installAllPlugins() }
                .buttonStyle(.borderedProminent)

            if !model.installMessage.isEmpty {
                Text(model.installMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.background.opacity(0.72)))
    }

    private var logsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP Debug Log")
                        .font(.title2.weight(.semibold))
                    Text("Polling \(LMNHPaths.mcpLogFile.path)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.logEntries.count) lines")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            logView
        }
    }

    private var cursorOptionsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cursorHeader
                cursorThemeGrid
                cursorControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cursorHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Virtual Cursor")
                .font(.title2.weight(.semibold))
            CursorPreview(appearance: model.appearance)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var cursorThemeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            ForEach(VirtualCursorTheme.allCases) { theme in
                cursorThemeButton(theme)
            }
        }
    }

    private func cursorThemeButton(_ theme: VirtualCursorTheme) -> some View {
        let isSelected = model.appearance.normalized.theme == theme
        return Button {
            model.applyTheme(theme)
        } label: {
            HStack(spacing: 12) {
                CursorThemeThumbnail(appearance: previewAppearance(for: theme))
                    .frame(width: 44, height: 40)
                Text(theme.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var cursorControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.appearance.normalized.theme.usesTint {
                SliderRow(title: "Red", value: $model.appearance.red, range: 0...1)
                SliderRow(title: "Green", value: $model.appearance.green, range: 0...1)
                SliderRow(title: "Blue", value: $model.appearance.blue, range: 0...1)
            } else if let attribution = VirtualCursorArtwork.attribution(for: model.appearance.normalized.theme) {
                Text(attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SliderRow(title: "Scale", value: $model.appearance.scale, range: 0.5...2.5)
            SliderRow(title: "Easing Duration", value: $model.appearance.animationDuration, range: 0.05...2.0)

            HStack {
                Button("Save") { model.saveAppearance() }
                    .keyboardShortcut("s")
                Button("Reset Pink") { model.resetAppearance() }
            }
            .buttonStyle(.borderedProminent)

            if !model.saveMessage.isEmpty {
                Text(model.saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func previewAppearance(for theme: VirtualCursorTheme) -> VirtualCursorAppearance {
        var appearance = theme.defaultAppearance
        appearance.scale = 1
        return appearance
    }

    private var logView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("time").frame(width: 92, alignment: .leading)
                Text("status").frame(width: 56, alignment: .leading)
                Text("tool").frame(width: 190, alignment: .leading)
                Text("message").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.22))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.logEntries) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .background(.black.opacity(0.16))
                .onChange(of: model.logEntries) { _, entries in
                    guard let last = entries.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private enum RightPane: String, CaseIterable, Identifiable {
    case cursorOptions
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logs: "Logs"
        case .cursorOptions: "Cursor Options"
        }
    }

    var systemImage: String {
        switch self {
        case .logs: "list.bullet.rectangle"
        case .cursorOptions: "cursorarrow"
        }
    }
}
