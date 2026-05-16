import Foundation

public actor MCPRequestRouter {
    private let toolRouter: MCPToolRouter
    private let serverName: String
    private let serverVersion: String

    public init(
        toolRouter: MCPToolRouter,
        serverName: String = "look-mum-no-hands",
        serverVersion: String = "0.1.0"
    ) {
        self.toolRouter = toolRouter
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    public func process(_ payload: Data) async -> Data? {
        let decoder = JSONDecoder()
        let request: MCPJSONRPCRequest

        do {
            request = try decoder.decode(MCPJSONRPCRequest.self, from: payload)
        } catch {
            return encodeResponse(
                MCPJSONRPCResponse(
                    id: .null,
                    error: MCPJSONRPCError(
                        code: MCPProtocolErrorCode.parseError,
                        message: "Parse error",
                        data: .string(error.localizedDescription)
                    )
                )
            )
        }

        guard request.hasID else {
            return nil
        }

        guard request.jsonrpc == nil || request.jsonrpc == "2.0" else {
            return errorResponse(
                id: responseID(for: request),
                code: MCPProtocolErrorCode.invalidRequest,
                message: "Invalid JSON-RPC version."
            )
        }

        let response: MCPJSONRPCResponse

        switch request.method {
        case "initialize":
            response = MCPJSONRPCResponse(
                id: responseID(for: request),
                result: initializeResult(params: request.params)
            )
        case "notifications/initialized":
            response = MCPJSONRPCResponse(id: responseID(for: request), result: .object([:]))
        case "ping":
            response = MCPJSONRPCResponse(id: responseID(for: request), result: .object([:]))
        case "tools/list":
            response = await MCPJSONRPCResponse(
                id: responseID(for: request),
                result: .object([
                    "tools": .array(toolRouter.listTools().map(\.jsonValue))
                ])
            )
        case "tools/call":
            response = await handleToolCall(request)
        case "resources/list":
            response = MCPJSONRPCResponse(
                id: responseID(for: request),
                result: .object(["resources": .array([])])
            )
        case "resources/read":
            response = MCPJSONRPCResponse(
                id: responseID(for: request),
                error: MCPJSONRPCError(
                    code: MCPProtocolErrorCode.invalidParams,
                    message: "No MCP resources are implemented in this transport slice."
                )
            )
        case "prompts/list":
            response = MCPJSONRPCResponse(
                id: responseID(for: request),
                result: .object(["prompts": .array([])])
            )
        case "prompts/get":
            response = MCPJSONRPCResponse(
                id: responseID(for: request),
                error: MCPJSONRPCError(
                    code: MCPProtocolErrorCode.invalidParams,
                    message: "No MCP prompts are implemented in this transport slice."
                )
            )
        default:
            response = MCPJSONRPCResponse(
                id: responseID(for: request),
                error: MCPJSONRPCError(
                    code: MCPProtocolErrorCode.methodNotFound,
                    message: "Method not found: \(request.method)"
                )
            )
        }

        return encodeResponse(response)
    }

    private func initializeResult(params: MCPJSONValue?) -> MCPJSONValue {
        let requestedVersion = params?
            .objectValue?["protocolVersion"]?
            .stringValue

        return .object([
            "protocolVersion": .string(requestedVersion ?? "2024-11-05"),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(true)]),
                "resources": .object([
                    "subscribe": .bool(false),
                    "listChanged": .bool(true)
                ]),
                "prompts": .object(["listChanged": .bool(false)])
            ]),
            "serverInfo": .object([
                "name": .string(serverName),
                "version": .string(serverVersion)
            ])
        ])
    }

    private func handleToolCall(_ request: MCPJSONRPCRequest) async -> MCPJSONRPCResponse {
        let id = responseID(for: request)

        guard let params = request.params?.objectValue else {
            return MCPJSONRPCResponse(
                id: id,
                error: MCPJSONRPCError(
                    code: MCPProtocolErrorCode.invalidParams,
                    message: "tools/call requires object params."
                )
            )
        }

        guard let name = params["name"]?.stringValue else {
            return MCPJSONRPCResponse(
                id: id,
                error: MCPJSONRPCError(
                    code: MCPProtocolErrorCode.invalidParams,
                    message: "tools/call requires a string name."
                )
            )
        }

        let arguments: MCPJSONObject
        switch params["arguments"] {
        case nil, .null:
            arguments = [:]
        case let .object(value):
            arguments = value
        default:
            return MCPJSONRPCResponse(
                id: id,
                error: MCPJSONRPCError(
                    code: MCPProtocolErrorCode.invalidParams,
                    message: "tools/call arguments must be an object when provided."
                )
            )
        }

        let result = await toolRouter.callTool(name: name, arguments: arguments)
        return MCPJSONRPCResponse(id: id, result: result.jsonValue)
    }

    private func responseID(for request: MCPJSONRPCRequest) -> MCPJSONValue {
        request.id ?? .null
    }

    private func errorResponse(id: MCPJSONValue, code: Int, message: String) -> Data? {
        encodeResponse(
            MCPJSONRPCResponse(
                id: id,
                error: MCPJSONRPCError(code: code, message: message)
            )
        )
    }

    private func encodeResponse(_ response: MCPJSONRPCResponse) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(response)
    }
}
