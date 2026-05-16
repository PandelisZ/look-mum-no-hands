import Foundation

public struct MCPJSONRPCRequest: Decodable, Sendable {
    public let jsonrpc: String?
    public let id: MCPJSONValue?
    public let hasID: Bool
    public let method: String
    public let params: MCPJSONValue?

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc)
        hasID = container.contains(.id)
        id = try container.decodeIfPresent(MCPJSONValue.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(MCPJSONValue.self, forKey: .params)
    }
}

public struct MCPJSONRPCResponse: Encodable, Sendable {
    public let jsonrpc: String
    public let id: MCPJSONValue?
    public let result: MCPJSONValue?
    public let error: MCPJSONRPCError?

    public init(
        id: MCPJSONValue?,
        result: MCPJSONValue? = nil,
        error: MCPJSONRPCError? = nil
    ) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPJSONRPCError: Codable, Equatable, Sendable {
    public let code: Int
    public let message: String
    public let data: MCPJSONValue?

    public init(code: Int, message: String, data: MCPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public enum MCPProtocolErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

public struct MCPContent: Equatable, Sendable {
    public let type: String
    public let text: String?
    public let data: String?
    public let mimeType: String?

    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }

    public static func text(_ text: String) -> MCPContent {
        MCPContent(type: "text", text: text)
    }

    public static func image(data: String, mimeType: String) -> MCPContent {
        MCPContent(type: "image", data: data, mimeType: mimeType)
    }

    public var jsonValue: MCPJSONValue {
        var object: MCPJSONObject = ["type": .string(type)]

        if let text {
            object["text"] = .string(text)
        }

        if let data {
            object["data"] = .string(data)
        }

        if let mimeType {
            object["mimeType"] = .string(mimeType)
        }

        return .object(object)
    }
}

public struct MCPToolResult: Equatable, Sendable {
    public let content: [MCPContent]
    public let structuredContent: MCPJSONValue?
    public let isError: Bool

    public init(
        content: [MCPContent],
        structuredContent: MCPJSONValue? = nil,
        isError: Bool = false
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }

    public static func text(
        _ text: String,
        structuredContent: MCPJSONValue? = nil,
        isError: Bool = false
    ) -> MCPToolResult {
        MCPToolResult(
            content: [.text(text)],
            structuredContent: structuredContent,
            isError: isError
        )
    }

    public var jsonValue: MCPJSONValue {
        var object: MCPJSONObject = [
            "content": .array(content.map(\.jsonValue)),
            "isError": .bool(isError)
        ]

        if let structuredContent {
            object["structuredContent"] = structuredContent
        }

        return .object(object)
    }
}

public struct MCPToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: MCPJSONValue
    public let annotations: MCPJSONValue?

    public init(
        name: String,
        description: String,
        inputSchema: MCPJSONValue,
        annotations: MCPJSONValue? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
    }

    public var jsonValue: MCPJSONValue {
        var object: MCPJSONObject = [
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ]

        if let annotations {
            object["annotations"] = annotations
        }

        return .object(object)
    }
}
