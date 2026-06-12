import ApplicationServices
import Foundation

@MainActor
public protocol LMNHMacOSAutomationServing: Sendable {
    func permissionStatus(arguments: MCPJSONObject) async -> MCPToolResult
    func openApp(arguments: MCPJSONObject) async -> MCPToolResult
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
    func scroll(arguments: MCPJSONObject) async -> MCPToolResult
    func pressKey(arguments: MCPJSONObject) async -> MCPToolResult
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

    public func openApp(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.openApp, summary: "App launcher service is not wired yet.")
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

    public func scroll(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.scroll, summary: "Scroll service is not wired yet.")
    }

    public func pressKey(arguments: MCPJSONObject) async -> MCPToolResult {
        placeholderResult(toolName: LMNHMCPTools.pressKey, summary: "Key press service is not wired yet.")
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
    private let appLauncher: AppLauncher
    private let windowInventory: WindowInventory
    private let snapshotService: SnapshotService
    private let screenshotService: ScreenshotService
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
        self.appLauncher = AppLauncher()
        self.snapshotService = SnapshotService(
            elementRegistry: elementRegistry,
            permissionReader: permissionReader,
            windowInventory: windowInventory,
            axClient: axClient
        )
        self.screenshotService = ScreenshotService()
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

    public func openApp(arguments: MCPJSONObject) async -> MCPToolResult {
        let result = await appLauncher.openApp(
            bundleIdentifier: arguments["bundle_id"]?.stringValue,
            appPath: arguments["app_path"]?.stringValue,
            appName: arguments["app_name"]?.stringValue,
            background: arguments["background"]?.boolValue ?? true,
            restoreFocus: arguments["restore_focus"]?.boolValue ?? true
        )

        return encodedToolResult(
            summary: result.status == "completed"
                ? "Opened \(result.launchedApplicationName ?? result.bundleIdentifier ?? result.requested) with focus policy \(result.focusPolicy.rawValue)."
                : "Failed to open \(result.requested): \(result.error ?? "unknown error")",
            structuredContent: [
                "launch": result
            ],
            isError: result.status != "completed"
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
            snapshot.warnings.append("Inline snapshot screenshots are not supported; call macos_get_screenshot instead.")
        }

        if arguments["include_ocr"]?.boolValue == true {
            snapshot.warnings.append("OCR is not wired in this MCP transport slice.")
        }

        let llmSnapshot = LLMSnapshotFormatter.format(snapshot)
        return MCPToolResult.text(
            llmSnapshot.text,
            isError: false
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
        let role = normalizeRole(arguments["role"]?.stringValue)
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
        .sorted { left, right in
            elementSearchScore(left, query: query) > elementSearchScore(right, query: query)
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
        let target = arguments["target"]?.stringValue ?? "frontmost_window"
        var elementFrame: LMNHRect?
        var elementPID: Int32?

        if target == "element" {
            guard let snapshotID = arguments["snapshot_id"]?.stringValue,
                  let elementID = arguments["element_id"]?.stringValue else {
                return missingArgumentResult(
                    toolName: LMNHMCPTools.getScreenshot,
                    required: ["snapshot_id and element_id when target is element"]
                )
            }
            guard let element = snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: elementID) else {
                return staleElementResult(snapshotID: snapshotID, elementID: elementID)
            }
            elementFrame = element.record.frame
            elementPID = element.record.processIdentifier
        }

        let format = ScreenshotImageFormat(rawValue: arguments["format"]?.stringValue ?? "png") ?? .png
        let request = ScreenshotRequest(
            target: target,
            windowID: arguments["window_id"]?.intValue.map(UInt32.init),
            displayID: arguments["display_id"]?.intValue.map(UInt32.init),
            elementFrame: elementFrame,
            elementProcessIdentifier: elementPID,
            maxWidth: arguments["max_width"]?.intValue ?? 1568,
            format: format
        )

        do {
            let capture = try await screenshotService.capture(request)
            guard let metadata = try? MCPJSONValue.encoded(capture.metadata) else {
                return MCPToolResult(
                    content: [.image(data: capture.base64Data, mimeType: format.mimeType)],
                    isError: false
                )
            }
            return MCPToolResult(
                content: [
                    .text("Captured \(target) screenshot (\(capture.metadata.pixelWidth)x\(capture.metadata.pixelHeight)px)."),
                    .image(data: capture.base64Data, mimeType: format.mimeType)
                ],
                structuredContent: .object(["screenshot": metadata]),
                isError: false
            )
        } catch let error as ScreenshotServiceError {
            var object: MCPJSONObject = [
                "tool": .string(LMNHMCPTools.getScreenshot),
                "status": .string("failed"),
                "reason": .string(error.reason),
                "target": .string(target)
            ]
            if case .permissionDenied = error {
                object["remediation"] = .string(
                    "Grant Screen & System Audio Recording permission in System Settings > Privacy & Security, then restart the MCP client."
                )
            }
            return MCPToolResult.text(
                "Screenshot failed: \(error.reason)",
                structuredContent: .object(object),
                isError: true
            )
        } catch {
            return MCPToolResult.text(
                "Screenshot failed: \(error.localizedDescription)",
                structuredContent: .object([
                    "tool": .string(LMNHMCPTools.getScreenshot),
                    "status": .string("failed"),
                    "reason": .string(error.localizedDescription)
                ]),
                isError: true
            )
        }
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
                "Text method \(method) is not focusless in this transport slice; no keyboard or paste fallback was attempted.",
                structuredContent: .object([
                    "method": .string(method),
                    "status": .string("not_implemented"),
                    "focus_policy": .string("no_focus_change"),
                    "execution_layer": .string(ActionExecutionLayer.semanticAX.rawValue),
                    "real_mouse_moved": .bool(false),
                    "fallback_policy": .string("keyboard_and_paste_not_attempted_to_preserve_focus"),
                    "integration_todo": .string("Wire an explicit opt-in pasteboard or keystroke text entry service that reports focus handoff.")
                ]),
                isError: true
            )
        }

        guard let mode = TextEntryMutationMode(rawValue: arguments["mode"]?.stringValue ?? "replace") else {
            return MCPToolResult.text(
                "macos_type_text mode must be replace, append, or selection.",
                structuredContent: .object([
                    "tool": .string(LMNHMCPTools.typeText),
                    "status": .string("invalid_arguments"),
                    "valid_modes": .array(["replace", "append", "selection"].map { .string($0) })
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

        var textEntry = actionExecutor.setText(
            snapshotId: snapshotID,
            elementId: elementID,
            text: text,
            mode: mode,
            confirmationToken: arguments["confirmation_token"]?.stringValue
        )

        if arguments["submit"]?.boolValue == true {
            textEntry.diagnostics.submitAction = AXNames.Action.confirm
            if textEntry.action.status != .completed {
                textEntry.diagnostics.submitStatus = "skipped_text_entry_failed"
            } else if element.record.actions.contains(AXNames.Action.confirm) {
                let submitResult = actionExecutor.performAction(
                    snapshotId: snapshotID,
                    elementId: elementID,
                    action: AXNames.Action.confirm,
                    confirmationToken: arguments["confirmation_token"]?.stringValue
                )
                textEntry.diagnostics.submitStatus = submitResult.status.rawValue
                textEntry.action.warnings.append(contentsOf: submitResult.warnings)
            } else {
                textEntry.diagnostics.submitStatus = "unsupported_element_has_no_axconfirm_action"
            }
        }

        let result = textEntry.action
        let cursor = setCursor(
            for: result,
            element: element.record,
            state: result.status == .completed ? .typing : .blocked,
            sessionID: arguments["session_id"]?.stringValue ?? "default"
        )

        return textEntryToolResult(
            summary: result.status == .completed
                ? "Updated text on \(elementID) with focusless AXValue \(mode.rawValue)."
                : "Failed focusless AXValue \(mode.rawValue) on \(elementID).",
            result: result,
            diagnostics: textEntry.diagnostics,
            virtualCursor: cursor
        )
    }

    public func scroll(arguments: MCPJSONObject) async -> MCPToolResult {
        guard let directionRaw = arguments["direction"]?.stringValue,
              let direction = TargetedEventDispatcher.ScrollDirection(rawValue: directionRaw) else {
            return MCPToolResult.text(
                "macos_scroll requires direction up, down, left, or right.",
                structuredContent: .object([
                    "tool": .string(LMNHMCPTools.scroll),
                    "status": .string("invalid_arguments"),
                    "valid_directions": .array(["up", "down", "left", "right"].map { .string($0) })
                ]),
                isError: true
            )
        }

        let snapshotID = arguments["snapshot_id"]?.stringValue
        let elementID = arguments["element_id"]?.stringValue
        if elementID != nil && snapshotID == nil {
            return missingArgumentResult(toolName: LMNHMCPTools.scroll, required: ["snapshot_id when element_id is supplied"])
        }

        let element = snapshotID.flatMap { snapshotID in
            elementID.flatMap { snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: $0) }
        }

        let result = actionExecutor.scroll(
            snapshotId: snapshotID,
            elementId: elementID,
            point: makePoint(arguments: arguments),
            direction: direction,
            pages: arguments["pages"]?.doubleValue ?? 1,
            targetProcessIdentifier: arguments["target_pid"]?.intValue.map(Int32.init)
        )
        let cursor = setCursor(for: result, element: element?.record, state: result.status == .completed ? .scrolling : .blocked)

        return actionToolResult(
            summary: result.status == .completed
                ? "Scrolled \(direction.rawValue) without moving the real mouse."
                : "Scroll \(direction.rawValue) failed before moving the real mouse.",
            result: result,
            virtualCursor: cursor
        )
    }

    public func pressKey(arguments: MCPJSONObject) async -> MCPToolResult {
        guard let key = arguments["key"]?.stringValue, !key.isEmpty else {
            return missingArgumentResult(toolName: LMNHMCPTools.pressKey, required: ["key"])
        }

        let snapshotID = arguments["snapshot_id"]?.stringValue
        let elementID = arguments["element_id"]?.stringValue
        let element = snapshotID.flatMap { snapshotID in
            elementID.flatMap { snapshotService.elementRegistry.resolve(snapshotId: snapshotID, elementId: $0) }
        }

        let result = actionExecutor.pressKey(
            snapshotId: snapshotID,
            elementId: elementID,
            keyCombination: key,
            targetProcessIdentifier: arguments["target_pid"]?.intValue.map(Int32.init)
        )
        let cursor = setCursor(for: result, element: element?.record, state: result.status == .completed ? .typing : .blocked)

        return actionToolResult(
            summary: result.status == .completed
                ? "Pressed \(key) without moving the real mouse."
                : "Failed to press \(key).",
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

    private func normalizeRole(_ role: String?) -> String? {
        guard let role, !role.isEmpty else {
            return nil
        }
        if role.hasPrefix("AX") {
            return role
        }
        return "AX" + role.prefix(1).uppercased() + role.dropFirst()
    }

    private func elementSearchScore(_ record: AccessibilityElementRecord, query: String?) -> Int {
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = record.label?.lowercased()
        let title = record.title?.lowercased()
        let description = record.description?.lowercased()
        let value = record.valuePreview?.lowercased()
        var score = 0

        if record.visible { score += 100 }
        if record.enabled != false { score += 20 }
        if record.role == "AXButton" { score += 80 }
        if record.defaultAction != nil { score += 60 }
        if record.actions.contains(AXNames.Action.press) { score += 50 }
        if record.role == "AXStaticText" { score -= 30 }
        if record.role == "AXMenuItem" || record.role == "AXMenuBarItem" { score -= 40 }

        if let query, !query.isEmpty {
            if label == query { score += 200 }
            if title == query { score += 160 }
            if description == query { score += 120 }
            if value == query { score += 50 }
            if label?.contains(query) == true { score += 40 }
            if title?.contains(query) == true { score += 30 }
            if description?.contains(query) == true { score += 20 }
            if value?.contains(query) == true { score += 10 }
        }

        return score
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
        let windowFrame = windowInventory
            .listWindows()
            .filter { $0.ownerPID == element.processIdentifier && $0.layer == 0 && $0.isOnscreen && $0.bounds?.isUsableFrame == true }
            .max { left, right in
                overlapArea(left.bounds, element.frame) < overlapArea(right.bounds, element.frame)
            }?
            .bounds
            .map { VirtualCursorFrame(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        return VirtualCursorTarget(
            appBundleID: element.bundleIdentifier,
            processIdentifier: element.processIdentifier,
            windowFrame: windowFrame,
            elementID: element.id,
            frame: frame,
            point: frame?.center
        )
    }

    private func overlapArea(_ lhs: LMNHRect?, _ rhs: LMNHRect?) -> Double {
        guard let lhs, let rhs else { return 0 }
        let xOverlap = max(0, min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x))
        let yOverlap = max(0, min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y))
        return xOverlap * yOverlap
    }

    private func setCursor(
        for result: MacOSActionResult,
        element: AccessibilityElementRecord?,
        state: VirtualCursorState,
        sessionID: String = "default"
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
            cursorID: "cursor_\(sessionID)",
            sessionID: sessionID,
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
        let compact = CompactActionResult(action: result, cursor: virtualCursor)
        return encodedToolResult(
            summary: compact.text,
            structuredContent: [
                "action": compact
            ],
            isError: result.status == .failed
        )
    }

    private func textEntryToolResult(
        summary: String,
        result: MacOSActionResult,
        diagnostics: TextEntryDiagnostics,
        virtualCursor: VirtualCursorRecord
    ) -> MCPToolResult {
        let compact = CompactTextEntryResult(action: result, diagnostics: diagnostics, cursor: virtualCursor)
        return encodedToolResult(
            summary: compact.action.text,
            structuredContent: [
                "typing": compact
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
        case LMNHMCPTools.openApp:
            await service.openApp(arguments: arguments)
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
        case LMNHMCPTools.scroll:
            await service.scroll(arguments: arguments)
        case LMNHMCPTools.pressKey:
            await service.pressKey(arguments: arguments)
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
