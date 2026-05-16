import Foundation

public enum MCPMessageFramerError: Error, Equatable, Sendable {
    case invalidHeaderEncoding
    case invalidContentLength(String)
}

public struct MCPMessageFramer: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)

        var messages: [Data] = []

        while true {
            removeLeadingLineBreaks()

            if buffer.isEmpty {
                break
            }

            if startsWithContentLengthHeader() {
                guard let headerEnd = headerTerminatorRange() else {
                    break
                }

                let headerData = buffer.subdata(in: 0..<headerEnd.range.lowerBound)
                guard let header = String(data: headerData, encoding: .utf8) else {
                    throw MCPMessageFramerError.invalidHeaderEncoding
                }

                let contentLength = try parseContentLength(from: header)
                let bodyStart = headerEnd.range.upperBound
                let messageEnd = bodyStart + contentLength

                guard buffer.count >= messageEnd else {
                    break
                }

                messages.append(buffer.subdata(in: bodyStart..<messageEnd))
                buffer.removeSubrange(0..<messageEnd)
                continue
            }

            guard let newlineIndex = buffer.firstIndex(of: 0x0A) else {
                break
            }

            let line = trimmedLineData(buffer.subdata(in: 0..<newlineIndex))
            buffer.removeSubrange(0...newlineIndex)

            if !line.isEmpty {
                messages.append(line)
            }
        }

        return messages
    }

    private mutating func removeLeadingLineBreaks() {
        while let first = buffer.first, first == 0x0A || first == 0x0D {
            buffer.removeFirst()
        }
    }

    private func startsWithContentLengthHeader() -> Bool {
        let prefix = Data("Content-Length:".utf8)

        guard buffer.count >= prefix.count else {
            return prefix.starts(with: buffer)
        }

        return buffer.prefix(prefix.count).caseInsensitiveASCIIEquals(prefix)
    }

    private func headerTerminatorRange() -> (range: Range<Int>, length: Int)? {
        if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
            return (range, 4)
        }

        if let range = buffer.range(of: Data("\n\n".utf8)) {
            return (range, 2)
        }

        return nil
    }

    private func parseContentLength(from header: String) throws -> Int {
        for line in header.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare("Content-Length") == .orderedSame else {
                continue
            }

            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let contentLength = Int(value), contentLength >= 0 else {
                throw MCPMessageFramerError.invalidContentLength(value)
            }

            return contentLength
        }

        throw MCPMessageFramerError.invalidContentLength(header)
    }

    private func trimmedLineData(_ data: Data) -> Data {
        var lowerBound = data.startIndex
        var upperBound = data.endIndex

        while lowerBound < upperBound, isJSONWhitespace(data[lowerBound]) {
            lowerBound = data.index(after: lowerBound)
        }

        while upperBound > lowerBound {
            let previous = data.index(before: upperBound)
            guard isJSONWhitespace(data[previous]) else {
                break
            }
            upperBound = previous
        }

        return data.subdata(in: lowerBound..<upperBound)
    }

    private func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}

private extension Data {
    func caseInsensitiveASCIIEquals(_ other: Data) -> Bool {
        guard count == other.count else {
            return false
        }

        return zip(self, other).allSatisfy { lhs, rhs in
            lhs.asciiLowercased == rhs.asciiLowercased
        }
    }
}

private extension UInt8 {
    var asciiLowercased: UInt8 {
        if self >= 0x41, self <= 0x5A {
            self + 0x20
        } else {
            self
        }
    }
}
