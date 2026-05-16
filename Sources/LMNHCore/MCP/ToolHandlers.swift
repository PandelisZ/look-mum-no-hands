import ApplicationServices
import Foundation

@MainActor
public protocol LMNHMacOSAutomationServing: Sendable {
    func permissionStatus(arguments: MCPJSONObject) async -> MCPToolResult
    func listApps(arguments: MCPJSONObject) async -> MCPToolResult
    func listWindows(arguments: MCPJSONObject) async -> MCPToolResult
    func snapshot(arguments: MCPJSONObject) async -> MCPToolResult
    func getElement(arguments: MCPJSONObject) async -> MCPToolResult
    func findElements(arguments: MCPJSONObject) async -> MCPToolResult
    func getScreenshot(arguments: MCPJSONObject) async -> MCPToolResult
    func setVirtualCursor(arguments: MCPJSONObject) async -> MCPToolResult
    func hideVirtualCursor(arguments: MCPJSONObject) async -> MCPToolResult
    func performAction(arguments: MCPJSONObject) async -> MCPToolResult
    func click(arguments: MCPJSONObject) async -> MCPToolResult
    func typeText(arguments: MCPJSONObject) async -> MCPToolResult
}

public struct PlaceholderMacOSAutomationService: LMNHMacOSAutomationServing, Sendable {
    public init() {}

    public func permissionStatus(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.permissionStatus,
            summary: "Permission status service is not wired yet."
        )
    }

    public func listApps(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.listApps,
            summary: "Running application service is not wired yet."
        )
    }

    public func listWindows(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.listWindows, summary: "Window listing service is not wired yet.")
    }

    public func snapshot(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.snapshot,
            summary: "Snapshot service is not wired yet."
        )
    }

    public func getElement(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.getElement, summary: "Element lookup service is not wired yet.")
    }

    public func findElements(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.findElements, summary: "Element search service is not wired yet.")
    }

    public func getScreenshot(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.getScreenshot, summary: "Screenshot service is not wired yet.")
    }

    public func setVirtualCursor(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.setVirtualCursor,
            summary: "Virtual cursor service is not wired yet."
        )
    }

    public func hideVirtualCursor(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.hideVirtualCursor,
            summary: "Virtual cursor service is not wired yet."
        )
    }

    public func performAction(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.performAction,
            summary: "Semantic action service is not wired yet."
        )
    }

    public func click(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.click,
            summary: "Focusless click service is not wired yet."
        )
    }

    public func typeText(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(
            toolName: LMNHMCPTools.typeText,
            summary: "Text entry service is not wired yet."
        )
    }

    private func placeholderResult(toolName: String, summary: String) -> MCPToolResult {
        MCPToolResult.text(
            "\(toolName) is routed, but \(summary)",
            structuredContent: .object([
                "tool": .string(toolName),
                "status": .string("not_implemented"),
                "integration_todo": .string(summary)
            ]),
            isError: true
        )
    }
}

@MainActor
public final class DefaultMacOSAutomationService: LMNHMacOSAutomationServing, @unchecked Sendable {
    private let permissionReader: PermissionStatusReader
    private let applicationProvider: RunningApplicationProvider
    private let windowInventory: WindowInventory
    private let snapshotService: SnapshotService
    private let cursorController: VirtualCursorController
    private let actionExecutor: ActionExecutor

    public init(
        permissionReader: PermissionStatusReader = PermissionStatusReader(),
        windowInventory: WindowInventory = WindowInventory(),
        elementRegistry: ElementRegistry = ElementRegistry(),
        axClient: AXClient = AXClient(),
        virtualCursorRenderMode: VirtualCursorRenderMode = .automatic
    ) {
        self.permissionReader = permissionReader
        self.windowInventory = windowInventory
        self.applicationProvider = RunningApplicationProvider(windowInventory: windowInventory)
        self.snapshotService = SnapshotService(
            elementRegistry: elementRegistry,
            permissionReader: permissionReader,
            windowInventory: windowInventory,
            axClient: axClient
        )
        _ = VirtualCursorAppearance.load()
        self.cursorController = VirtualCursorController(mode: virtualCursorRenderMode)
        self.actionExecutor = ActionExecutor(elementRegistry: elementRegistry, axClient: axClient)
    }

    public func permissionStatus(arguments: MCPJSONObject) async -> MCPToolResult {
        let status = permissionReader.current(promptForAccessibility: arguments["prompt"]?.boolValue ?? false)
        return encodedToolResult(
            summary: "Accessibility: \(status.accessibility.rawValue); Screen Recording: \(status.screenCapture.rawValue).",
            structuredContent: [
                "permission_status": status
            ]
        )
    }

    public func listApps(arguments: MCPJSONObject) async -> MCPToolResult {
        let includeBackground = arguments["include_background"]?.boolValue ?? true
        let applications = applicationProvider.listRunningApplications(includeBackgroundAgents: includeBackground)

        return encodedToolResult(
            summary: "Listed \(applications.count) running applications.",
            structuredContent: [
                "applications": applications
            ]
        )
    }

    public func listWindows(arguments: MCPJSONObject) async -> MCPToolResult {
        let windows = windowInventory.listWindows(onscreenOnly: arguments["onscreen_only"]?.boolValue ?? true)
        return encodedToolResult(
            summary: "Listed \(windows.count) windows.",
            structuredContent: [
                "windows": windows
            ]
        )
    }

    public func snapshot(arguments: MCPJSONObject) async -> MCPToolResult {
        let mode = SnapshotMode(rawValue: arguments["mode"]?.stringValue ?? "") ?? .standard
        let request = MacOSSnapshotRequest(
            mode: mode,
            targetBundleIdentifier: arguments["app_bundle_id"]?.stringValue,
            maxDepth: arguments["max_depth"]?.intValue ?? 8,
            maxNodes: arguments["max_nodes"]?.intValue ?? 750,
            includeBackgroundAgents: true
        )

        var snapshot = snapshotService.capture(request)
        snapshot.virtualCursors = cursorController.listCursors()

        if arguments["include_screenshot"]?.boolValue == true {
            snapshot.warnings.append("Screenshot capture is not wired in this MCP transport slice.")
        }

        if arguments["include_ocr"]?.boolValue == true {
            snapshot.warnings.append("OCR is not wired in this MCP transport slice.")
        }

        return encodedToolResult(
            summary: "Captured snapshot \(snapshot.id) with \(snapshot.applications.count) apps, \(snapshot.windows.count) windows, and \(snapshot.accessibilityTree.count) accessibility elements.",
            structuredContent: [
                "snapshot": snapshot
            ]
        )
    }

    public func getElement(arguments: MCPJSONObject) async -> MCPToolResult {
        guard let snapshotID = arguments["snapshot_id"]?.stringValue,
              let elementID = arguments["element_id"]?.stringValue else {
            return missingArgumentResult(toolName: LMNHMCPTools.getElement, required: ["snapshot_id", "element_id"])
        }

        guard let element = snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: elementID) else {
            return staleElementResult(snapshotID: snapshotID, elementID: elementID)
        }

        return encodedToolResult(
            summary: "Found element \(elementID).",
            structuredContent: [
                "element": element.record
            ]
        )
    }

    public func findElements(arguments: MCPJSONObject) async -> MCPToolResult {
        guard let snapshotID = arguments["snapshot_id"]?.stringValue else {
            return missingArgumentResult(toolName: LMNHMCPTools.findElements, required: ["snapshot_id"])
        }

        let query = arguments["query"]?.stringValue?.lowercased()
        let role = arguments["role"]?.stringValue
        let visibleOnly = arguments["visible_only"]?.boolValue ?? true
        let limit = arguments["limit"]?.intValue ?? 20
        let records = snapshotService.elementRegistry.records(snapshotId: snapshotID)
        let matches = records.filter { record in
            if visibleOnly && !record.visible {
                return false
            }
            if let role, record.role != role {
                return false
            }
            guard let query, !query.isEmpty else {
                return true
            }
            return [
                record.title,
                record.label,
                record.description,
                record.valuePreview,
                record.selector,
                record.role,
                record.subrole,
                record.path.joined(separator: " ")
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
        .prefix(max(1, limit))

        return encodedToolResult(
            summary: "Found \(matches.count) elements in \(snapshotID).",
            structuredContent: [
                "snapshot_id": snapshotID,
                "elements": Array(matches)
            ]
        )
    }

    public func getScreenshot(arguments: MCPJSONObject) async -> MCPToolResult {
        MCPToolResult.text(
            "Screenshot capture is planned but not wired in this MVP slice. Use macos_snapshot for structured UI state.",
            structuredContent: .object([
                "status": .string("not_implemented"),
                "target": arguments["target"] ?? .string("frontmost_window"),
                "integration_todo": .string("Wire ScreenCaptureKit SCScreenshotManager/window capture.")
            ]),
            isError: true
        )
    }

    public func setVirtualCursor(arguments: MCPJSONObject) async -> MCPToolResult {
        let sessionID = arguments["session_id"]?.stringValue ?? "default"
        let cursorID = "cursor_\(sessionID)"
        let state = VirtualCursorState(rawValue: arguments["state"]?.stringValue ?? "") ?? .aiming
        let coordinateSpace = arguments["coordinate_space"]?.stringValue ?? "global_display_points"
        let target = makeCursorTarget(arguments: arguments, statePointCoordinateSpace: coordinateSpace)
        let record = cursorController.setCursor(
            cursorID: cursorID,
            sessionID: sessionID,
            taskLabel: arguments["label"]?.stringValue,
            state: state,
            target: target
        )

        return encodedToolResult(
            summary: "Set virtual cursor \(record.cursorID) to \(record.state.rawValue).",
            structuredContent: [
                "virtual_cursor": record
            ]
        )
    }

    public func hideVirtualCursor(arguments: MCPJSONObject) async -> MCPToolResult {
        if arguments["all"]?.boolValue == true {
            cursorController.removeAllCursors()
            return MCPToolResult.text(
                "Hidden all virtual cursors.",
                structuredContent: .object(["hidden": .string("all")])
            )
        }

        if let cursorID = arguments["cursor_id"]?.stringValue {
            let record = cursorController.hideCursor(cursorID: cursorID)
            return encodedToolResult(
                summary: record == nil ? "No virtual cursor named \(cursorID) was visible." : "Hidden virtual cursor \(cursorID).",
                structuredContent: [
                    "virtual_cursor": record as VirtualCursorRecord?
                ]
            )
        }

        if let sessionID = arguments["session_id"]?.stringValue {
            let cursors = cursorController
                .listCursors(includeHidden: true)
                .filter { $0.sessionID == sessionID }
            for cursor in cursors {
                _ = cursorController.hideCursor(cursorID: cursor.cursorID)
            }
            return encodedToolResult(
                summary: "Hidden \(cursors.count) virtual cursors for session \(sessionID).",
                structuredContent: [
                    "hidden_cursor_ids": cursors.map(\.cursorID)
                ]
            )
        }

        return MCPToolResult.text(
            "Specify cursor_id, session_id, or all=true.",
            structuredContent: .object(["status": .string("invalid_arguments")]),
            isError: true
        )
    }

    public func performAction(arguments: MCPJSONObject) async -> MCPToolResult {
        guard let snapshotID = arguments["snapshot_id"]?.stringValue,
              let elementID = arguments["element_id"]?.stringValue,
              let action = arguments["action"]?.stringValue else {
            return missingArgumentResult(toolName: LMNHMCPTools.performAction, required: ["snapshot_id", "element_id", "action"])
        }

        guard let element = snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: elementID) else {
            return staleElementResult(snapshotID: snapshotID, elementID: elementID)
        }

        let result = actionExecutor.performAction(
            snapshotId: snapshotID,
            elementId: elementID,
            action: action,
            confirmationToken: arguments["confirmation_token"]?.stringValue
        )
        let cursor = setCursor(for: result, element: element.record, state: result.status == .completed ? .pressing : .blocked)

        return actionToolResult(
            summary: result.status == .completed ? "Performed \(action) on \(elementID)." : "Failed to perform \(action) on \(elementID).",
            result: result,
            virtualCursor: cursor
        )
    }

    public func click(arguments: MCPJSONObject) async -> MCPToolResult {
        let snapshotID = arguments["snapshot_id"]?.stringValue
        let elementID = arguments["element_id"]?.stringValue
        let point = makePoint(arguments: arguments)
        let targetPID = arguments["target_pid"]?.intValue.map(Int32.init)

        if elementID != nil && snapshotID == nil {
            return missingArgumentResult(toolName: LMNHMCPTools.click, required: ["snapshot_id when element_id is supplied"])
        }

        let element = snapshotID.flatMap { snapshotID in
            elementID.flatMap { snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: $0) }
        }

        let result = actionExecutor.click(
            snapshotId: snapshotID,
            elementId: elementID,
            point: point,
            targetProcessIdentifier: targetPID,
            confirmationToken: arguments["confirmation_token"]?.stringValue
        )
        let cursor = setCursor(for: result, element: element?.record, state: result.status == .completed ? .pressing : .blocked)

        return actionToolResult(
            summary: result.status == .completed ? "Click-like action completed without moving the real mouse." : "Click-like action failed before moving the real mouse.",
            result: result,
            virtualCursor: cursor
        )
    }

    public func typeText(arguments: MCPJSONObject) async -> MCPToolResult {
        guard let text = arguments["text"]?.stringValue else {
            return missingArgumentResult(toolName: LMNHMCPTools.typeText, required: ["text"])
        }

        let method = arguments["method"]?.stringValue ?? "auto"
        guard method == "auto" || method == "ax_set_value" else {
            return MCPToolResult.text(
                "Text method \(method) is not wired in this MCP transport slice.",
                structuredContent: .object([
                    "method": .string(method),
                    "status": .string("not_implemented"),
                    "integration_todo": .string("Wire pasteboard or keystroke text entry service.")
                ]),
                isError: true
            )
        }

        guard let snapshotID = arguments["snapshot_id"]?.stringValue,
              let elementID = arguments["element_id"]?.stringValue else {
            return missingArgumentResult(toolName: LMNHMCPTools.typeText, required: ["snapshot_id", "element_id"])
        }

        guard let element = snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: elementID) else {
            return staleElementResult(snapshotID: snapshotID, elementID: elementID)
        }

        let result = actionExecutor.setValue(
            snapshotId: snapshotID,
            elementId: elementID,
            value: text,
            confirmationToken: arguments["confirmation_token"]?.stringValue
        )
        let cursor = setCursor(for: result, element: element.record, state: result.status == .completed ? .typing : .blocked)

        return actionToolResult(
            summary: result.status == .completed ? "Set text on \(elementID) with AXValue." : "Failed to set text on \(elementID) with AXValue.",
            result: result,
            virtualCursor: cursor
        )
    }

    private func makePoint(arguments: MCPJSONObject) -> LMNHPoint? {
        guard case let .number(x)? = arguments["x"],
              case let .number(y)? = arguments["y"] else {
            return nil
        }

        return LMNHPoint(x: x, y: y)
    }

    private func makeCursorPoint(arguments: MCPJSONObject, coordinateSpace: String) -> VirtualCursorPoint? {
        guard case let .number(x)? = arguments["x"],
              case let .number(y)? = arguments["y"] else {
            return nil
        }

        return VirtualCursorPoint(x: x, y: y, coordinateSpace: coordinateSpace)
    }

    private func makeCursorTarget(arguments: MCPJSONObject, statePointCoordinateSpace coordinateSpace: String) -> VirtualCursorTarget {
        if let snapshotID = arguments["snapshot_id"]?.stringValue,
           let elementID = arguments["element_id"]?.stringValue,
           let element = snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: elementID) {
            return cursorTarget(for: element.record)
        }

        return VirtualCursorTarget(
            elementID: arguments["element_id"]?.stringValue,
            point: makeCursorPoint(arguments: arguments, coordinateSpace: coordinateSpace)
        )
    }

    private func cursorTarget(for element: AccessibilityElementRecord) -> VirtualCursorTarget {
        let frame = element.frame.map {
            VirtualCursorFrame(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        return VirtualCursorTarget(
            appBundleID: element.bundleIdentifier,
            elementID: element.id,
            frame: frame,
            point: frame?.center
        )
    }

    private func setCursor(
        for result: MacOSActionResult,
        element: AccessibilityElementRecord?,
        state: VirtualCursorState
    ) -> VirtualCursorRecord {
        let point = result.point.map {
            VirtualCursorPoint(x: $0.x, y: $0.y)
        }
        let fallbackTarget = VirtualCursorTarget(
            appBundleID: result.targetBundleIdentifier,
            elementID: result.elementId,
            point: point
        )
        let target = element.map(cursorTarget(for:)) ?? fallbackTarget
        return cursorController.setCursor(
            cursorID: "cursor_default",
            sessionID: "default",
            state: state,
            target: target,
            lastToolCallID: result.actionId,
            lastExecutionLayer: result.executionLayer.rawValue,
            realMouseMoved: result.realMouseMoved,
            focusPolicy: VirtualCursorFocusPolicy(rawValue: result.focusPolicy.rawValue) ?? .failedBeforeFocusChange
        )
    }

    private func actionToolResult(
        summary: String,
        result: MacOSActionResult,
        virtualCursor: VirtualCursorRecord
    ) -> MCPToolResult {
        encodedToolResult(
            summary: summary,
            structuredContent: [
                "action": result,
                "virtual_cursor": virtualCursor
            ],
            isError: result.status == .failed
        )
    }

    private func encodedToolResult(
        summary: String,
        structuredContent: [String: any Encodable],
        isError: Bool = false
    ) -> MCPToolResult {
        var object: MCPJSONObject = [:]

        for (key, value) in structuredContent {
            if let encoded = try? MCPJSONValue.encoded(value) {
                object[key] = encoded
            } else {
                object[key] = .object([
                    "status": .string("encoding_failed")
                ])
            }
        }

        return MCPToolResult.text(
            summary,
            structuredContent: .object(object),
            isError: isError
        )
    }

    private func missingArgumentResult(toolName: String, required: [String]) -> MCPToolResult {
        MCPToolResult.text(
            "\(toolName) requires \(required.joined(separator: ", ")).",
            structuredContent: .object([
                "tool": .string(toolName),
                "status": .string("invalid_arguments"),
                "required": .array(required.map { .string($0) })
            ]),
            isError: true
        )
    }

    private func staleElementResult(snapshotID: String, elementID: String) -> MCPToolResult {
        MCPToolResult.text(
            "Element \(elementID) was not found in snapshot \(snapshotID). Call macos_snapshot again.",
            structuredContent: .object([
                "snapshot_id": .string(snapshotID),
                "element_id": .string(elementID),
                "status": .string("stale_element")
            ]),
            isError: true
        )
    }
}

public actor MCPToolRouter {
    private let service: any LMNHMacOSAutomationServing

    public init(service: any LMNHMacOSAutomationServing) {
        self.service = service
    }

    public func listTools() -> [MCPToolDefinition] {
        LMNHMCPTools.allDefinitions
    }

    public func callTool(name: String, arguments: MCPJSONObject) async -> MCPToolResult {
        let result = switch name {
        case LMNHMCPTools.permissionStatus:
            await service.permissionStatus(arguments: arguments)
        case LMNHMCPTools.listApps:
            await service.listApps(arguments: arguments)
        case LMNHMCPTools.listWindows:
            await service.listWindows(arguments: arguments)
        case LMNHMCPTools.snapshot:
            await service.snapshot(arguments: arguments)
        case LMNHMCPTools.getElement:
            await service.getElement(arguments: arguments)
        case LMNHMCPTools.findElements:
            await service.findElements(arguments: arguments)
        case LMNHMCPTools.getScreenshot:
            await service.getScreenshot(arguments: arguments)
        case LMNHMCPTools.setVirtualCursor:
            await service.setVirtualCursor(arguments: arguments)
        case LMNHMCPTools.hideVirtualCursor:
            await service.hideVirtualCursor(arguments: arguments)
        case LMNHMCPTools.performAction:
            await service.performAction(arguments: arguments)
        case LMNHMCPTools.click:
            await service.click(arguments: arguments)
        case LMNHMCPTools.typeText:
            await service.typeText(arguments: arguments)
        default:
            MCPToolResult.text(
                "Unknown tool: \(name)",
                structuredContent: .object([
                    "tool": .string(name),
                    "status": .string("unknown_tool")
                ]),
                isError: true
            )
        }
        await MCPCommandAuditLogger.shared.log(toolName: name, arguments: arguments, result: result)
        return result
    }
}
