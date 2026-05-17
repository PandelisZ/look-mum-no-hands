import AppKit
import LMNHCore
import SwiftUI

@main
struct LMNHControlApp: App {
    @StateObject private var model = ControlPanelModel()

    init() {
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("Look Mum No Hands") {
            ControlPanelView(model: model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("LMNH") {
                Button("Start HTTP MCP Server") { model.startMCPServer() }
                    .disabled(model.isMCPServerRunning)
                Button("Stop HTTP MCP Server") { model.stopMCPServer() }
                    .disabled(!model.isMCPServerRunning)
                Button("Copy HTTP MCP URL") { model.copyMCPServerURL() }
                Divider()
                Button("Install Cursor MCP Plugin") { model.installCursorPlugin() }
                Button("Install Codex MCP Plugin") { model.installCodexPlugin() }
                Button("Install Claude MCP Plugin") { model.installClaudePlugin() }
                Button("Install Cursor + Codex + Claude Plugins") { model.installAllPlugins() }
                Divider()
                Button("Reveal Project") { model.revealProject() }
            }
        }
    }
}

@MainActor
final class ControlPanelModel: ObservableObject {
    @Published var permissionStatus: MacOSPermissionStatus = PermissionStatusReader().current()
    @Published var appearance: VirtualCursorAppearance = .load()
    @Published var logEntries: [LogEntry] = []
    @Published var saveMessage: String = ""
    @Published var installMessage: String = ""
    @Published var isMCPServerRunning: Bool = false
    @Published var mcpServerPort: UInt16 = HTTPMCPServer.defaultPort
    @Published var mcpServerURL: String = "http://127.0.0.1:\(HTTPMCPServer.defaultPort)\(HTTPMCPServer.defaultPath)"

    private let permissionReader = PermissionStatusReader()
    private var timer: Timer?
    private var httpMCPServer: HTTPMCPServer?

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
        logEntries = readTail(of: LMNHPaths.mcpLogFile, maxLines: 160)
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

    func requestAccessibilityPermission() {
        permissionStatus = permissionReader.current(promptForAccessibility: true)
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
        saveAppearance()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func startMCPServer() {
        guard !isMCPServerRunning else {
            return
        }

        let service = DefaultMacOSAutomationService()
        let router = MCPRequestRouter(toolRouter: MCPToolRouter(service: service))
        let server = HTTPMCPServer(router: router, port: mcpServerPort)
        httpMCPServer = server
        installMessage = "Starting HTTP MCP server..."

        Task { @MainActor in
            do {
                let status = try await server.start(port: mcpServerPort)
                isMCPServerRunning = status.isRunning
                mcpServerPort = status.port
                mcpServerURL = status.url
                installMessage = "HTTP MCP server listening at \(status.url). Cursor/Codex stdio configs still launch lmnh-mcp."
            } catch {
                httpMCPServer = nil
                isMCPServerRunning = false
                installMessage = "Failed to start HTTP MCP server: \(error.localizedDescription)"
            }
        }
    }

    func stopMCPServer() {
        guard let server = httpMCPServer else {
            installMessage = "No HTTP MCP server is running."
            return
        }

        Task {
            await server.stop()
        }
        httpMCPServer = nil
        isMCPServerRunning = false
        installMessage = "Stopped HTTP MCP server."
    }

    func copyMCPServerURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcpServerURL, forType: .string)
        installMessage = "Copied HTTP MCP URL: \(mcpServerURL)"
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
        guard let codexCommand = Self.resolvedExecutable(named: "codex") else {
            installMessage = "Failed to install Codex MCP plugin: codex CLI was not found in PATH, ~/.local/bin, Homebrew, fnm, or nvm installs."
            return
        }

        let command = """
        \(Self.shellQuote(codexCommand)) mcp remove look-mum-no-hands-dev >/dev/null 2>&1 || true
        \(Self.shellQuote(codexCommand)) mcp add look-mum-no-hands-dev -- \(Self.shellQuote(Self.mcpBinaryURL.path))
        """
        let result = Self.runShell(command)
        if result.status == 0 {
            installMessage = "Installed Codex MCP plugin: look-mum-no-hands-dev"
        } else {
            installMessage = "Failed to install Codex MCP plugin: \(result.output)"
        }
    }

    func installClaudePlugin() {
        let claudeCommand = Self.resolvedExecutable(named: "claude")
        let binaryPath = Self.mcpBinaryURL.path
        let skillSource = LMNHPaths.projectRoot
            .appending(path: "plugins", directoryHint: .isDirectory)
            .appending(path: "look-mum-no-hands", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
            .appending(path: "look-mum-no-hands", directoryHint: .isDirectory)
        let claudeSkillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "skills", directoryHint: .isDirectory)
        let skillDestination = claudeSkillsDir.appending(path: "look-mum-no-hands", directoryHint: .isDirectory)

        var messages: [String] = []

        if let claudeCommand {
            let command = """
            \(Self.shellQuote(claudeCommand)) mcp remove look-mum-no-hands-dev >/dev/null 2>&1 || true
            \(Self.shellQuote(claudeCommand)) mcp add --scope user look-mum-no-hands-dev -- \(Self.shellQuote(binaryPath))
            """
            let result = Self.runShell(command)
            if result.status == 0 {
                messages.append("Registered Claude MCP server: look-mum-no-hands-dev")
            } else {
                messages.append("Failed to register Claude MCP server: \(result.output)")
            }
        } else {
            messages.append("Failed to register Claude MCP server: claude CLI was not found in PATH, ~/.local/bin, Homebrew, fnm, or nvm installs.")
        }

        do {
            try FileManager.default.createDirectory(at: claudeSkillsDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: skillDestination.path) {
                try FileManager.default.removeItem(at: skillDestination)
            }
            try FileManager.default.createSymbolicLink(at: skillDestination, withDestinationURL: skillSource)
            messages.append("Linked Claude skill at \(skillDestination.path)")
        } catch {
            messages.append("Failed to link Claude skill: \(error.localizedDescription)")
        }

        installMessage = messages.joined(separator: "\n")
    }

    func installAllPlugins() {
        installCursorPlugin()
        let cursorMessage = installMessage
        installCodexPlugin()
        let codexMessage = installMessage
        installClaudePlugin()
        installMessage = "\(cursorMessage)\n\(codexMessage)\n\(installMessage)"
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

    private static func resolvedExecutable(named executableName: String) -> String? {
        let fileManager = FileManager.default
        for directory in executableSearchDirectories() {
            let candidate = directory.appending(path: executableName).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func executableSearchDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories: [URL] = []

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }

        directories.append(contentsOf: [
            home.appending(path: ".local/bin", directoryHint: .isDirectory),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true)
        ])

        directories.append(contentsOf: versionedNodeBinDirectories(in: home.appending(path: ".local/share/fnm/node-versions", directoryHint: .isDirectory)) {
            $0.appending(path: "installation/bin", directoryHint: .isDirectory)
        })
        directories.append(contentsOf: versionedNodeBinDirectories(in: home.appending(path: ".nvm/versions/node", directoryHint: .isDirectory)) { $0 })

        var seen: Set<String> = []
        return directories.filter { directory in
            let path = directory.path
            guard !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
    }

    private static func versionedNodeBinDirectories(
        in root: URL,
        transform: (URL) -> URL
    ) -> [URL] {
        guard let versionDirectories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return versionDirectories
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map(transform)
    }

    private static func runShell(_ command: String) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = LMNHPaths.projectRoot
        process.environment = shellEnvironment()
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

    private static func shellEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let searchPath = executableSearchDirectories().map(\.path).joined(separator: ":")
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(searchPath):\(existingPath)"
        } else {
            environment["PATH"] = searchPath
        }
        return environment
    }
}
