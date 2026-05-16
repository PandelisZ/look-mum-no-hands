import Foundation
import LMNHCore

public final class MCPServer {
    private let input: FileHandle
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let router: MCPRequestRouter
    private let outputFraming: MCPOutputFraming

    public init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        errorOutput: FileHandle = .standardError,
        router: MCPRequestRouter,
        outputFraming: MCPOutputFraming = .environmentDefault
    ) {
        self.input = input
        self.output = output
        self.errorOutput = errorOutput
        self.router = router
        self.outputFraming = outputFraming
    }

    public func run() async throws {
        var framer = MCPMessageFramer()

        while true {
            let chunk = input.readData(ofLength: 1)
            guard !chunk.isEmpty else {
                break
            }

            let payloads = try framer.append(chunk)
            for payload in payloads {
                guard let response = await router.process(payload) else {
                    continue
                }

                write(response)
            }
        }
    }

    public func logError(_ message: String) {
        errorOutput.write(Data((message + "\n").utf8))
    }

    private func write(_ response: Data) {
        switch outputFraming {
        case .newlineJSON:
            output.write(response)
            output.write(Data("\n".utf8))
        case .contentLength:
            writeFramed(response)
        }
    }

    private func writeFramed(_ response: Data) {
        let header = Data("Content-Length: \(response.count)\r\n\r\n".utf8)
        output.write(header)
        output.write(response)
    }
}

public enum MCPOutputFraming: Sendable {
    case newlineJSON
    case contentLength

    public static var environmentDefault: MCPOutputFraming {
        ProcessInfo.processInfo.environment["LMNH_MCP_OUTPUT_FRAMING"] == "content_length"
            ? .contentLength
            : .newlineJSON
    }
}
