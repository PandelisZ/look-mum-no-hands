import Foundation

public typealias MCPJSONObject = [String: MCPJSONValue]

public enum MCPJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([MCPJSONValue])
    case object(MCPJSONObject)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(MCPJSONObject.self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            if value.isFinite,
               value.rounded(.towardZero) == value,
               value >= Double(Int64.min),
               value <= Double(Int64.max) {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public var objectValue: MCPJSONObject? {
        if case let .object(value) = self {
            value
        } else {
            nil
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self {
            value
        } else {
            nil
        }
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self {
            value
        } else {
            nil
        }
    }

    public var doubleValue: Double? {
        if case let .number(value) = self {
            value
        } else {
            nil
        }
    }

    public var intValue: Int? {
        if case let .number(value) = self,
           value.rounded(.towardZero) == value,
           value >= Double(Int.min),
           value <= Double(Int.max) {
            Int(value)
        } else {
            nil
        }
    }

    public static func integer(_ value: Int) -> MCPJSONValue {
        .number(Double(value))
    }

    public static func encoded<T: Encodable>(_ value: T) throws -> MCPJSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(MCPJSONValue.self, from: data)
    }
}
