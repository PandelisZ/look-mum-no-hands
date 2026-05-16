import Foundation

public struct RedactedValue: Codable, Sendable, Equatable {
    public var preview: String?
    public var length: Int?
    public var truncated: Bool
    public var available: Bool
    public var reasons: [String]

    public init(preview: String?, length: Int?, truncated: Bool, available: Bool, reasons: [String] = []) {
        self.preview = preview
        self.length = length
        self.truncated = truncated
        self.available = available
        self.reasons = reasons
    }
}

public struct Redactor: Sendable {
    public var maxPreviewCharacters: Int

    public init(maxPreviewCharacters: Int = 500) {
        self.maxPreviewCharacters = maxPreviewCharacters
    }

    public func preview(_ value: Any?, role: String?, isSecureTextEntry: Bool) -> RedactedValue {
        if isSecureTextEntry {
            return RedactedValue(
                preview: "<redacted>",
                length: nil,
                truncated: false,
                available: false,
                reasons: ["secure text entry"]
            )
        }

        guard let value else {
            return RedactedValue(preview: nil, length: nil, truncated: false, available: true)
        }

        let string = stringify(value)
        guard !string.isEmpty else {
            return RedactedValue(preview: "", length: 0, truncated: false, available: true)
        }

        let redacted = redactSensitivePatterns(in: string)
        let length = redacted.count
        if length > maxPreviewCharacters {
            let end = redacted.index(redacted.startIndex, offsetBy: maxPreviewCharacters)
            return RedactedValue(
                preview: String(redacted[..<end]),
                length: length,
                truncated: true,
                available: true
            )
        }

        return RedactedValue(preview: redacted, length: length, truncated: false, available: true)
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            string
        case let attributed as NSAttributedString:
            attributed.string
        case let number as NSNumber:
            number.stringValue
        case let url as URL:
            url.absoluteString
        default:
            String(describing: value)
        }
    }

    private func redactSensitivePatterns(in value: String) -> String {
        var result = value
        let patterns = [
            #"(?i)sk-[a-z0-9_-]{16,}"#,
            #"(?i)(api[_-]?key|token|secret)\s*[:=]\s*[\w.-]{8,}"#,
            #"\b(?:\d[ -]*?){13,19}\b"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return result
    }
}
