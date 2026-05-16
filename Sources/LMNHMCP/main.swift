import Darwin
import Foundation
import LMNHCore

let service = await MainActor.run {
    DefaultMacOSAutomationService()
}
let router = MCPRequestRouter(toolRouter: MCPToolRouter(service: service))
let server = MCPServer(router: router)

do {
    try await server.run()
} catch {
    server.logError("lmnh-mcp failed: \(error)")
    Darwin.exit(1)
}
