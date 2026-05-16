import Foundation

public enum LMNHPaths {
    public static var projectRoot: URL {
        if let override = ProcessInfo.processInfo.environment["LMNH_PROJECT_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: cwd.appending(path: "Package.swift").path) {
            return cwd
        }

        return URL(fileURLWithPath: "/Users/pz/w/look-mum-no-hands", isDirectory: true)
    }

    public static var stateDirectory: URL {
        projectRoot.appending(path: ".lmnh-agent", directoryHint: .isDirectory)
    }

    public static var logsDirectory: URL {
        stateDirectory.appending(path: "logs", directoryHint: .isDirectory)
    }

    public static var cursorAppearanceFile: URL {
        stateDirectory.appending(path: "cursor-appearance.json")
    }

    public static var mcpLogFile: URL {
        logsDirectory.appending(path: "mcp.jsonl")
    }

    public static func ensureStateDirectories() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}
