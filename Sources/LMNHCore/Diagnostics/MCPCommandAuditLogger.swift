import Foundation

public struct MCPCommandAuditEntry: Codable, Sendable {
    public var timestamp: Date
    public var toolName: String
    public var arguments: MCPJSONValue
    public var isError: Bool
    public var summary: String?

    public init(toolName: String, arguments: MCPJSONValue, isError: Bool, summary: String?) {
        self.timestamp = Date()
        self.toolName = toolName
        self.arguments = arguments
        self.isError = isError
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case toolName = "tool_name"
        case arguments
        case isError = "is_error"
        case summary
    }
}

public actor MCPCommandAuditLogger {
    public static let shared = MCPCommandAuditLogger()

    private let encoder: JSONEncoder

    public init() {
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public func log(toolName: String, arguments: MCPJSONObject, result: MCPToolResult) {
        let entry = MCPCommandAuditEntry(
            toolName: toolName,
            arguments: .object(redact(arguments)),
            isError: result.isError,
            summary: result.content.first?.text
        )

        write(entry)
    }

    public func logServerEvent(
        transport: String,
        method: String,
        path: String,
        statusCode: Int,
        isError: Bool
    ) {
        let entry = MCPCommandAuditEntry(
            toolName: "\(transport)_\(method)",
            arguments: .object([
                "transport": .string(transport),
                "method": .string(method),
                "path": .string(path),
                "status_code": .integer(statusCode)
            ]),
            isError: isError,
            summary: "\(transport.uppercased()) MCP \(method) -> \(statusCode)"
        )

        write(entry)
    }

    private func write(_ entry: MCPCommandAuditEntry) {
        guard let data = try? encoder.encode(entry) else {
            return
        }

        LMNHPaths.ensureStateDirectories()
        let line = data + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: LMNHPaths.mcpLogFile.path) {
            if let handle = try? FileHandle(forWritingTo: LMNHPaths.mcpLogFile) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            }
        } else {
            try? line.write(to: LMNHPaths.mcpLogFile, options: .atomic)
        }
    }

    private func redact(_ object: MCPJSONObject) -> MCPJSONObject {
        var redacted: MCPJSONObject = [:]
        for (key, value) in object {
            if key.localizedCaseInsensitiveContains("password")
                || key.localizedCaseInsensitiveContains("token")
                || key.localizedCaseInsensitiveContains("secret")
                || key.localizedCaseInsensitiveContains("credential") {
                redacted[key] = .string("<redacted>")
            } else {
                redacted[key] = redact(value)
            }
        }
        return redacted
    }

    private func redact(_ value: MCPJSONValue) -> MCPJSONValue {
        switch value {
        case .object(let object):
            .object(redact(object))
        case .array(let array):
            .array(array.map(redact))
        case .string(let string):
            string.count > 500 ? .string(String(string.prefix(500)) + "...<truncated>") : value
        default:
            value
        }
    }
}
