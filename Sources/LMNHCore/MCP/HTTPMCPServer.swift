import Foundation
@preconcurrency import Network

public struct HTTPMCPServerStatus: Codable, Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var path: String
    public var url: String
    public var isRunning: Bool

    public init(host: String, port: UInt16, path: String, isRunning: Bool) {
        self.host = host
        self.port = port
        self.path = path
        self.url = "http://\(host):\(port)\(path)"
        self.isRunning = isRunning
    }
}

public actor HTTPMCPServer {
    public static let defaultPort: UInt16 = 8765
    public static let defaultPath = "/mcp"

    private let router: MCPRequestRouter
    private let host: String
    private let path: String
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [UUID: NWConnection]
    private var port: UInt16

    public init(
        router: MCPRequestRouter,
        host: String = "127.0.0.1",
        port: UInt16 = HTTPMCPServer.defaultPort,
        path: String = HTTPMCPServer.defaultPath
    ) {
        self.router = router
        self.host = host
        self.port = port
        self.path = path.hasPrefix("/") ? path : "/\(path)"
        self.queue = DispatchQueue(label: "lmnh.http-mcp.server")
        self.connections = [:]
    }

    public var isRunning: Bool {
        listener != nil
    }

    public func status() -> HTTPMCPServerStatus {
        HTTPMCPServerStatus(host: host, port: port, path: path, isRunning: listener != nil)
    }

    @discardableResult
    public func start(port requestedPort: UInt16? = nil) throws -> HTTPMCPServerStatus {
        if listener != nil {
            return status()
        }

        let selectedPort = requestedPort ?? port
        guard let nwPort = NWEndpoint.Port(rawValue: selectedPort) else {
            throw HTTPMCPServerError.invalidPort(selectedPort)
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.service = nil
        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleListenerState(state)
            }
        }

        self.listener = listener
        self.port = selectedPort
        listener.start(queue: queue)
        return status()
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let actualPort = listener?.port?.rawValue {
                port = actualPort
            }
        case .failed:
            stop()
        case .cancelled:
            listener = nil
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task {
                    await self?.removeConnection(id)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(id: id, connection: connection, accumulated: Data())
    }

    private func receive(id: UUID, connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            var nextData = accumulated
            if let data {
                nextData.append(data)
            }

            if let request = HTTPMCPRequest.parse(nextData) {
                Task {
                    await self?.handle(request, id: id, connection: connection)
                }
                return
            }

            if isComplete || error != nil {
                Task {
                    await self?.send(
                        statusCode: 400,
                        reason: "Bad Request",
                        body: #"{"error":"invalid_http_request"}"#.data(using: .utf8) ?? Data(),
                        connection: connection,
                        id: id
                    )
                }
                return
            }

            Task {
                await self?.receive(id: id, connection: connection, accumulated: nextData)
            }
        }
    }

    private func handle(_ request: HTTPMCPRequest, id: UUID, connection: NWConnection) async {
        let methodName = (try? JSONDecoder().decode(MCPJSONRPCRequest.self, from: request.body).method) ?? "invalid_json"

        guard request.path == path else {
            await MCPCommandAuditLogger.shared.logServerEvent(
                transport: "http",
                method: methodName,
                path: request.path,
                statusCode: 404,
                isError: true
            )
            send(
                statusCode: 404,
                reason: "Not Found",
                body: #"{"error":"not_found"}"#.data(using: .utf8) ?? Data(),
                connection: connection,
                id: id
            )
            return
        }

        if request.method == "OPTIONS" {
            send(statusCode: 204, reason: "No Content", body: Data(), connection: connection, id: id)
            return
        }

        guard request.method == "POST" else {
            await MCPCommandAuditLogger.shared.logServerEvent(
                transport: "http",
                method: methodName,
                path: request.path,
                statusCode: 405,
                isError: true
            )
            send(
                statusCode: 405,
                reason: "Method Not Allowed",
                body: #"{"error":"method_not_allowed"}"#.data(using: .utf8) ?? Data(),
                connection: connection,
                id: id
            )
            return
        }

        guard let response = await router.process(request.body) else {
            await MCPCommandAuditLogger.shared.logServerEvent(
                transport: "http",
                method: methodName,
                path: request.path,
                statusCode: 202,
                isError: false
            )
            send(statusCode: 202, reason: "Accepted", body: Data(), connection: connection, id: id)
            return
        }

        await MCPCommandAuditLogger.shared.logServerEvent(
            transport: "http",
            method: methodName,
            path: request.path,
            statusCode: 200,
            isError: false
        )
        send(statusCode: 200, reason: "OK", body: response, connection: connection, id: id)
    }

    private func send(
        statusCode: Int,
        reason: String,
        body: Data,
        connection: NWConnection,
        id: UUID
    ) {
        var headers = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, OPTIONS",
            "Access-Control-Allow-Headers: content-type, mcp-session-id"
        ]
        if !body.isEmpty {
            headers.append("Content-Type: application/json")
        }

        var response = Data(headers.joined(separator: "\r\n").utf8)
        response.append(Data("\r\n\r\n".utf8))
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task {
                await self?.removeConnection(id)
            }
        })
    }

    private func removeConnection(_ id: UUID) {
        connections[id] = nil
    }
}

public enum HTTPMCPServerError: Error, LocalizedError, Sendable {
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            "Invalid HTTP MCP port \(port)."
        }
    }
}

private struct HTTPMCPRequest: Sendable {
    var method: String
    var path: String
    var body: Data

    static func parse(_ data: Data) -> HTTPMCPRequest? {
        let crlf = Data("\r\n\r\n".utf8)
        let lf = Data("\n\n".utf8)
        let headerRange: Range<Data.Index>
        let separatorLength: Int

        if let range = data.range(of: crlf) {
            headerRange = range
            separatorLength = crlf.count
        } else if let range = data.range(of: lf) {
            headerRange = range
            separatorLength = lf.count
        } else {
            return nil
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2)
        guard requestParts.count >= 2 else {
            return nil
        }

        let headers = lines.dropFirst().reduce(into: [String: String]()) { result, line in
            guard let separator = line.firstIndex(of: ":") else {
                return
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyOffset = headerRange.lowerBound + separatorLength
        guard data.count >= bodyOffset + contentLength else {
            return nil
        }

        let body = data[bodyOffset..<(bodyOffset + contentLength)]
        let path = String(requestParts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? String(requestParts[1])

        return HTTPMCPRequest(
            method: String(requestParts[0]).uppercased(),
            path: path,
            body: Data(body)
        )
    }
}
