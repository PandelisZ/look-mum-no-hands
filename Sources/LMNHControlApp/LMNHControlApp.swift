import AppKit
import LMNHCore
import SwiftUI

@main
struct LMNHControlApp: App {
    @StateObject private var model = ControlPanelModel()

    var body: some Scene {
        WindowGroup("Look Mum No Hands") {
            ControlPanelView(model: model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("LMNH") {
                Button("Start Diagnostic MCP Server") { model.startMCPServer() }
                    .disabled(model.isMCPServerRunning)
                Button("Stop Diagnostic MCP Server") { model.stopMCPServer() }
                    .disabled(!model.isMCPServerRunning)
                Divider()
                Button("Install Cursor MCP Plugin") { model.installCursorPlugin() }
                Button("Install Codex MCP Plugin") { model.installCodexPlugin() }
                Button("Install Cursor + Codex Plugins") { model.installAllPlugins() }
                Divider()
                Button("Reveal Project") { model.revealProject() }
            }
        }
    }
}

@MainActor
private final class ControlPanelModel: ObservableObject {
    @Published var permissionStatus: MacOSPermissionStatus = PermissionStatusReader().current()
    @Published var appearance: VirtualCursorAppearance = .load()
    @Published var logEntries: [LogEntry] = []
    @Published var saveMessage: String = ""
    @Published var installMessage: String = ""
    @Published var isMCPServerRunning: Bool = false
    @Published var mcpServerPID: Int32?

    private let permissionReader = PermissionStatusReader()
    private var timer: Timer?
    private var mcpProcess: Process?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
        }
    }

    func refresh() {
        permissionStatus = permissionReader.current()
        appearance = VirtualCursorAppearance.load()
        logEntries = readTail(of: LMNHPaths.mcpLogFile, maxLines: 160)
        if let mcpProcess, !mcpProcess.isRunning {
            self.mcpProcess = nil
            isMCPServerRunning = false
            mcpServerPID = nil
        }
    }

    func saveAppearance() {
        do {
            try appearance.save()
            saveMessage = "Saved cursor appearance"
            refresh()
        } catch {
            saveMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    func resetAppearance() {
        appearance = .defaultPink
        saveAppearance()
    }

    func applyTheme(_ theme: VirtualCursorTheme) {
        let previous = appearance.normalized
        var next = theme.defaultAppearance
        next.alpha = previous.alpha
        next.scale = previous.scale
        next.animationDuration = previous.animationDuration
        next.showLabels = previous.showLabels
        next.showPath = previous.showPath
        appearance = next
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func startMCPServer() {
        guard mcpProcess?.isRunning != true else {
            return
        }

        let process = Process()
        process.executableURL = Self.mcpBinaryURL
        process.currentDirectoryURL = LMNHPaths.projectRoot
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LMNH_PROJECT_ROOT": LMNHPaths.projectRoot.path
        ]) { _, new in new }
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.installMessage = "Diagnostic MCP server exited with status \(finished.terminationStatus)"
                self?.isMCPServerRunning = false
                self?.mcpServerPID = nil
                self?.mcpProcess = nil
            }
        }

        do {
            try process.run()
            mcpProcess = process
            isMCPServerRunning = true
            mcpServerPID = process.processIdentifier
            installMessage = "Started diagnostic MCP server (pid \(process.processIdentifier)). Cursor/Codex still launch their own MCP server instances."
        } catch {
            installMessage = "Failed to start MCP server: \(error.localizedDescription)"
        }
    }

    func stopMCPServer() {
        guard let process = mcpProcess else {
            installMessage = "No diagnostic MCP server is running."
            return
        }

        process.terminate()
        mcpProcess = nil
        isMCPServerRunning = false
        mcpServerPID = nil
        installMessage = "Stopped diagnostic MCP server."
    }

    func installCursorPlugin() {
        do {
            let cursorDirectory = LMNHPaths.projectRoot.appending(path: ".cursor", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
            let config: [String: Any] = [
                "mcpServers": [
                    "look-mum-no-hands-dev": [
                        "command": Self.mcpBinaryURL.path,
                        "args": [],
                        "env": [
                            "LMNH_LOG_LEVEL": "debug"
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: cursorDirectory.appending(path: "mcp.json"), options: .atomic)
            installMessage = "Installed Cursor MCP plugin config at .cursor/mcp.json"
        } catch {
            installMessage = "Failed to install Cursor MCP plugin: \(error.localizedDescription)"
        }
    }

    func installCodexPlugin() {
        let command = """
        codex mcp remove look-mum-no-hands-dev >/dev/null 2>&1 || true
        codex mcp add look-mum-no-hands-dev -- \(Self.shellQuote(Self.mcpBinaryURL.path))
        """
        let result = Self.runShell(command)
        if result.status == 0 {
            installMessage = "Installed Codex MCP plugin: look-mum-no-hands-dev"
        } else {
            installMessage = "Failed to install Codex MCP plugin: \(result.output)"
        }
    }

    func installAllPlugins() {
        installCursorPlugin()
        let cursorMessage = installMessage
        installCodexPlugin()
        installMessage = "\(cursorMessage)\n\(installMessage)"
    }

    func revealProject() {
        NSWorkspace.shared.activateFileViewerSelecting([LMNHPaths.projectRoot])
    }

    private func readTail(of url: URL, maxLines: Int) -> [LogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [
                LogEntry(
                    timestamp: "--",
                    status: "info",
                    tool: "lmnh",
                    summary: "No MCP command log yet. Calls will appear in \(url.path)."
                )
            ]
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxLines)
        return lines.map(formatLogLine)
    }

    private func formatLogLine(_ line: Substring) -> LogEntry {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LogEntry(timestamp: "--", status: "raw", tool: "log", summary: String(line))
        }
        let timestamp = object["timestamp"] as? String ?? "unknown-time"
        let tool = object["tool_name"] as? String ?? "unknown-tool"
        let summary = object["summary"] as? String ?? ""
        let isError = (object["is_error"] as? Bool) == true
        return LogEntry(
            timestamp: Self.shortTimestamp(timestamp),
            status: isError ? "error" : "ok",
            tool: tool,
            summary: summary
        )
    }

    private static func shortTimestamp(_ timestamp: String) -> String {
        guard let time = timestamp.split(separator: "T").last else {
            return timestamp
        }
        return String(time.replacingOccurrences(of: "Z", with: ""))
    }

    private static var mcpBinaryURL: URL {
        LMNHPaths.projectRoot
            .appending(path: ".build", directoryHint: .isDirectory)
            .appending(path: "debug", directoryHint: .isDirectory)
            .appending(path: "lmnh-mcp")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runShell(_ command: String) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = LMNHPaths.projectRoot
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (1, error.localizedDescription)
        }
    }
}

private struct ControlPanelView: View {
    @ObservedObject var model: ControlPanelModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                header
                permissionCard
                serverCard
                cursorCard
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(width: 360)
            .background(.regularMaterial)

            Divider()

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
            .padding(24)
        }
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
                Text(model.isMCPServerRunning ? "Diagnostic server running" : "Diagnostic server stopped")
                Spacer()
                if let pid = model.mcpServerPID {
                    Text("pid \(pid)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Start") { model.startMCPServer() }
                    .disabled(model.isMCPServerRunning)
                Button("Stop") { model.stopMCPServer() }
                    .disabled(!model.isMCPServerRunning)
            }
            .buttonStyle(.bordered)

            HStack {
                Button("Install Cursor") { model.installCursorPlugin() }
                Button("Install Codex") { model.installCodexPlugin() }
            }
            .buttonStyle(.bordered)

            Button("Install Both Plugins") { model.installAllPlugins() }
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

    private var cursorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Virtual Cursor")
                .font(.headline)
            CursorPreview(appearance: model.appearance)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Picker("Mouse", selection: themeBinding) {
                ForEach(VirtualCursorTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.menu)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(VirtualCursorTheme.allCases) { theme in
                    Button(theme.displayName) {
                        model.applyTheme(theme)
                    }
                    .buttonStyle(.bordered)
                }
            }

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
            Toggle("Show labels", isOn: $model.appearance.showLabels)
            Toggle("Show path", isOn: $model.appearance.showPath)

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
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.background.opacity(0.72)))
    }

    private var themeBinding: Binding<VirtualCursorTheme> {
        Binding(
            get: { model.appearance.theme },
            set: { model.applyTheme($0) }
        )
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
