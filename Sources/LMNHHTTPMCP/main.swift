import Darwin
import Foundation
import LMNHCore

let port = parsePort()
let service = await MainActor.run {
    DefaultMacOSAutomationService()
}
let router = MCPRequestRouter(toolRouter: MCPToolRouter(service: service))
let server = HTTPMCPServer(router: router, port: port)

do {
    let status = try await server.start(port: port)
    print("LMNH HTTP MCP server listening at \(status.url)")
    fflush(stdout)
    while !Task.isCancelled {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
} catch {
    FileHandle.standardError.write(Data("lmnh-mcp-http failed: \(error.localizedDescription)\n".utf8))
    Darwin.exit(1)
}

private func parsePort() -> UInt16 {
    let arguments = CommandLine.arguments.dropFirst()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        if argument == "--port", let value = iterator.next(), let port = UInt16(value) {
            return port
        }
        if argument.hasPrefix("--port="),
           let port = UInt16(argument.replacingOccurrences(of: "--port=", with: "")) {
            return port
        }
    }

    if let value = ProcessInfo.processInfo.environment["LMNH_HTTP_MCP_PORT"],
       let port = UInt16(value) {
        return port
    }

    return HTTPMCPServer.defaultPort
}
