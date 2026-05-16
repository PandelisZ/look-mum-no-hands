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
    @Published var logLines: [String] = []
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
        logLines = readTail(of: LMNHPaths.mcpLogFile, maxLines: 80)
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
                            "LMNH_LOG_LEVEL": "debug",
                            "LMNH_PROJECT_ROOT": LMNHPaths.projectRoot.path
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

    private func readTail(of url: URL, maxLines: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["No MCP command log yet. Calls will appear in \(url.path)."]
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxLines)
        return lines.map(formatLogLine)
    }

    private func formatLogLine(_ line: Substring) -> String {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(line)
        }
        let timestamp = object["timestamp"] as? String ?? "unknown-time"
        let tool = object["tool_name"] as? String ?? "unknown-tool"
        let summary = object["summary"] as? String ?? ""
        let isError = (object["is_error"] as? Bool) == true ? "ERROR" : "ok"
        return "[\(timestamp)] \(isError) \(tool) - \(summary)"
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
                Text("MCP Debug Log")
                    .font(.title2.weight(.semibold))
                Text("Recent MCP tool calls from \(LMNHPaths.mcpLogFile.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Picker("Mouse", selection: $model.appearance.theme) {
                ForEach(VirtualCursorTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.menu)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(VirtualCursorTheme.allCases) { theme in
                    Button(theme.displayName) {
                        model.appearance = theme.defaultAppearance
                    }
                    .buttonStyle(.bordered)
                }
            }

            SliderRow(title: "Red", value: $model.appearance.red, range: 0...1)
            SliderRow(title: "Green", value: $model.appearance.green, range: 0...1)
            SliderRow(title: "Blue", value: $model.appearance.blue, range: 0...1)
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

    private var logView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.45)))
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let state: PermissionState

    var body: some View {
        HStack {
            Circle()
                .fill(state == .granted ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(title)
            Spacer()
            Text(state.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state == .granted ? .green : .red)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct CursorPreview: View {
    let appearance: VirtualCursorAppearance

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let progress = (sin(t * 2.2) + 1) / 2
                let eased = 1 - pow(1 - progress, 3)
                let start = CGPoint(x: 54, y: size.height - 34)
                let end = CGPoint(x: size.width - 70, y: 34)
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * eased,
                    y: start.y + (end.y - start.y) * eased
                )
                let color = Color(
                    red: appearance.normalized.red,
                    green: appearance.normalized.green,
                    blue: appearance.normalized.blue,
                    opacity: appearance.normalized.alpha
                )

                var path = Path()
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x, y: end.y),
                    control2: CGPoint(x: end.x, y: start.y)
                )
                context.stroke(path, with: .color(color.opacity(0.28)), style: StrokeStyle(lineWidth: 3, dash: [6, 7]))
                context.stroke(Path(ellipseIn: CGRect(center: end, radius: 12)), with: .color(color.opacity(0.7)), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(center: start, radius: 5)), with: .color(color.opacity(0.4)))
                context.fill(cursorPath(at: point, scale: appearance.normalized.scale), with: .color(color))
                context.stroke(cursorPath(at: point, scale: appearance.normalized.scale), with: .color(.white.opacity(0.92)), lineWidth: 1.5)
            }
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.84), .purple.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func cursorPath(at point: CGPoint, scale: Double) -> Path {
        let s = CGFloat(scale)
        switch appearance.normalized.theme {
        case .pinkArrow, .classicMac, .windows2000:
            return arrowPath(at: point, scale: s)
        case .aquaBubble:
            return arrowPath(at: point, scale: s)
        case .limePixel:
            return pixelPath(at: point, scale: s)
        case .goldenGlove:
            return glovePath(at: point, scale: s)
        case .rocket:
            return rocketPath(at: point, scale: s)
        }
    }

    private func arrowPath(at point: CGPoint, scale s: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x + 10 * s, y: point.y + 34 * s))
        path.addLine(to: CGPoint(x: point.x + 28 * s, y: point.y + 18 * s))
        path.closeSubpath()
        return path
    }

    private func pixelPath(at point: CGPoint, scale s: CGFloat) -> Path {
        let unit = 5 * s
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x, y: point.y + 7 * unit))
        path.addLine(to: CGPoint(x: point.x + unit, y: point.y + 7 * unit))
        path.addLine(to: CGPoint(x: point.x + unit, y: point.y + 5 * unit))
        path.addLine(to: CGPoint(x: point.x + 2 * unit, y: point.y + 5 * unit))
        path.addLine(to: CGPoint(x: point.x + 2 * unit, y: point.y + 6 * unit))
        path.addLine(to: CGPoint(x: point.x + 3 * unit, y: point.y + 6 * unit))
        path.addLine(to: CGPoint(x: point.x + 3 * unit, y: point.y + 4 * unit))
        path.addLine(to: CGPoint(x: point.x + 5 * unit, y: point.y + 4 * unit))
        path.closeSubpath()
        return path
    }

    private func glovePath(at point: CGPoint, scale s: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addCurve(to: CGPoint(x: point.x + 8 * s, y: point.y + 28 * s), control1: CGPoint(x: point.x + 2 * s, y: point.y + 9 * s), control2: CGPoint(x: point.x + 4 * s, y: point.y + 19 * s))
        path.addCurve(to: CGPoint(x: point.x + 18 * s, y: point.y + 21 * s), control1: CGPoint(x: point.x + 12 * s, y: point.y + 30 * s), control2: CGPoint(x: point.x + 18 * s, y: point.y + 28 * s))
        path.addCurve(to: CGPoint(x: point.x + 30 * s, y: point.y + 10 * s), control1: CGPoint(x: point.x + 24 * s, y: point.y + 21 * s), control2: CGPoint(x: point.x + 30 * s, y: point.y + 17 * s))
        path.addCurve(to: CGPoint(x: point.x + 14 * s, y: point.y + 2 * s), control1: CGPoint(x: point.x + 29 * s, y: point.y + 1 * s), control2: CGPoint(x: point.x + 20 * s, y: point.y - 2 * s))
        path.closeSubpath()
        return path
    }

    private func rocketPath(at point: CGPoint, scale s: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x + 13 * s, y: point.y + 38 * s))
        path.addLine(to: CGPoint(x: point.x + 22 * s, y: point.y + 22 * s))
        path.addLine(to: CGPoint(x: point.x + 34 * s, y: point.y + 18 * s))
        path.addLine(to: CGPoint(x: point.x + 22 * s, y: point.y + 12 * s))
        path.addLine(to: CGPoint(x: point.x + 17 * s, y: point.y + 2 * s))
        path.closeSubpath()
        return path
    }
}

private extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
