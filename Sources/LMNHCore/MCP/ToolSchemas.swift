import Foundation

public enum LMNHMCPTools {
    public static let permissionStatus = "macos_permission_status"
    public static let openApp = "macos_open_app"
    public static let listApps = "macos_list_apps"
    public static let listWindows = "macos_list_windows"
    public static let snapshot = "macos_snapshot"
    public static let getElement = "macos_get_element"
    public static let findElements = "macos_find_elements"
    public static let getScreenshot = "macos_get_screenshot"
    public static let setVirtualCursor = "macos_set_virtual_cursor"
    public static let hideVirtualCursor = "macos_hide_virtual_cursor"
    public static let performAction = "macos_perform_action"
    public static let click = "macos_click"
    public static let typeText = "macos_type_text"
    public static let scroll = "macos_scroll"

    public static let allDefinitions: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: permissionStatus,
            description: "Report macOS Accessibility, Screen Recording, and input permission status.",
            inputSchema: objectSchema(properties: [:]),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: openApp,
            description: "Open a macOS application with background-launch intent and restore the previous frontmost app if macOS focuses the launched app.",
            inputSchema: objectSchema(
                properties: [
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string("Preferred application bundle identifier, e.g. com.apple.calculator.")
                    ]),
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string("Explicit .app path when bundle_id resolution is not available.")
                    ]),
                    "app_name": .object([
                        "type": .string("string"),
                        "description": .string("Reserved for future app-name resolution; prefer bundle_id or app_path.")
                    ]),
                    "background": .object([
                        "type": .string("boolean"),
                        "default": .bool(true)
                    ]),
                    "restore_focus": .object([
                        "type": .string("boolean"),
                        "default": .bool(true)
                    ])
                ]
            ),
            annotations: .object([
                "readOnlyHint": .bool(false),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(true)
            ])
        ),
        MCPToolDefinition(
            name: listApps,
            description: "List running macOS applications visible to the automation service.",
            inputSchema: objectSchema(properties: [
                "include_background": .object([
                    "type": .string("boolean"),
                    "default": .bool(true)
                ])
            ]),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: listWindows,
            description: "List visible macOS windows with owner, bounds, layer, and onscreen metadata.",
            inputSchema: objectSchema(properties: [:]),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: snapshot,
            description: "Capture a structured snapshot of current macOS UI state.",
            inputSchema: objectSchema(properties: [
                "mode": stringEnum(["summary", "standard", "full"], defaultValue: "standard"),
                "include_screenshot": .object([
                    "type": .string("boolean"),
                    "default": .bool(true)
                ]),
                "include_ocr": .object([
                    "type": .string("boolean"),
                    "default": .bool(true)
                ]),
                "app_bundle_id": .object([
                    "type": .string("string"),
                    "description": .string("Optional app bundle identifier to focus the snapshot on.")
                ]),
                "max_depth": .object([
                    "type": .string("integer"),
                    "default": .integer(10),
                    "minimum": .integer(0)
                ]),
                "max_nodes": .object([
                    "type": .string("integer"),
                    "default": .integer(1500),
                    "minimum": .integer(1)
                ])
            ]),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: getElement,
            description: "Return one element record from a captured snapshot.",
            inputSchema: objectSchema(
                properties: [
                    "snapshot_id": .object(["type": .string("string")]),
                    "element_id": .object(["type": .string("string")])
                ],
                required: ["snapshot_id", "element_id"]
            ),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: findElements,
            description: "Search element records in a captured snapshot by text, role, and visibility.",
            inputSchema: objectSchema(
                properties: [
                    "snapshot_id": .object(["type": .string("string")]),
                    "query": .object(["type": .string("string")]),
                    "role": .object(["type": .string("string")]),
                    "visible_only": .object(["type": .string("boolean"), "default": .bool(true)]),
                    "limit": .object(["type": .string("integer"), "default": .integer(20), "minimum": .integer(1)])
                ],
                required: ["snapshot_id"]
            ),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: getScreenshot,
            description: "Capture a pixel screenshot of the frontmost window, a specific window, a display, or a snapshot element region. Uses ScreenCaptureKit; never moves the real mouse or changes focus.",
            inputSchema: objectSchema(properties: [
                "target": stringEnum(["frontmost_window", "window", "display", "element"], defaultValue: "frontmost_window"),
                "snapshot_id": .object([
                    "type": .string("string"),
                    "description": .string("Snapshot id, required when target is element.")
                ]),
                "element_id": .object([
                    "type": .string("string"),
                    "description": .string("Element id, required when target is element.")
                ]),
                "window_id": .object([
                    "type": .string("integer"),
                    "description": .string("CGWindow id from macos_list_windows, required when target is window.")
                ]),
                "display_id": .object([
                    "type": .string("integer"),
                    "description": .string("Display id; defaults to the main display when target is display.")
                ]),
                "max_width": .object([
                    "type": .string("integer"),
                    "default": .integer(1568),
                    "minimum": .integer(64),
                    "description": .string("Downscale wider captures to this pixel width to keep payloads small.")
                ]),
                "format": stringEnum(["png", "jpeg"], defaultValue: "png")
            ]),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
        MCPToolDefinition(
            name: setVirtualCursor,
            description: "Move or update the visual-only virtual cursor without moving the real mouse.",
            inputSchema: objectSchema(properties: [
                "snapshot_id": .object(["type": .string("string")]),
                "element_id": .object(["type": .string("string")]),
                "x": .object(["type": .string("number")]),
                "y": .object(["type": .string("number")]),
                "coordinate_space": stringEnum(["global_display_points"], defaultValue: "global_display_points"),
                "state": stringEnum(
                    ["observing", "aiming", "pressing", "typing", "scrolling", "dragging", "blocked", "handoff"],
                    defaultValue: "aiming"
                ),
                "label": .object(["type": .string("string")]),
                "session_id": .object(["type": .string("string")])
            ]),
            annotations: .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(false)
            ])
        ),
        MCPToolDefinition(
            name: hideVirtualCursor,
            description: "Hide one virtual cursor, a session's cursors, or all virtual cursors.",
            inputSchema: objectSchema(properties: [
                "cursor_id": .object(["type": .string("string")]),
                "session_id": .object(["type": .string("string")]),
                "all": .object([
                    "type": .string("boolean"),
                    "default": .bool(false)
                ])
            ]),
            annotations: .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(false)
            ])
        ),
        MCPToolDefinition(
            name: performAction,
            description: "Perform a semantic accessibility action on a known element.",
            inputSchema: objectSchema(
                properties: [
                    "snapshot_id": .object(["type": .string("string")]),
                    "element_id": .object(["type": .string("string")]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Accessibility action such as AXPress.")
                    ]),
                    "confirmation_token": .object(["type": .string("string")])
                ],
                required: ["element_id", "action"]
            ),
            annotations: .object([
                "readOnlyHint": .bool(false),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(true)
            ])
        ),
        MCPToolDefinition(
            name: click,
            description: "Perform a click-like action without moving the real mouse when possible. Prefers AXPress by element id or AX element-at-position.",
            inputSchema: objectSchema(
                properties: [
                    "snapshot_id": .object(["type": .string("string")]),
                    "element_id": .object(["type": .string("string")]),
                    "x": .object(["type": .string("number")]),
                    "y": .object(["type": .string("number")]),
                    "target_pid": .object([
                        "type": .string("integer"),
                        "description": .string("Optional target process id for AXUIElementCopyElementAtPosition.")
                    ]),
                    "coordinate_space": stringEnum(["global_display_points"], defaultValue: "global_display_points"),
                    "confirmation_token": .object(["type": .string("string")])
                ]
            ),
            annotations: .object([
                "readOnlyHint": .bool(false),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(true)
            ])
        ),
        MCPToolDefinition(
            name: typeText,
            description: "Mutate text in a target input element without focusing the target window. Uses AXValue by default; paste and keystroke fallbacks are intentionally not attempted unless separately implemented.",
            inputSchema: objectSchema(
                properties: [
                    "snapshot_id": .object(["type": .string("string")]),
                    "element_id": .object(["type": .string("string")]),
                    "text": .object(["type": .string("string")]),
                    "method": stringEnum(["auto", "ax_set_value", "keystrokes", "paste"], defaultValue: "auto"),
                    "mode": stringEnum(["replace", "append", "selection"], defaultValue: "replace"),
                    "submit": .object([
                        "type": .string("boolean"),
                        "default": .bool(false),
                        "description": .string("After a successful text mutation, perform the element's AXConfirm action (focusless submit). Reported as unsupported when the element exposes no AXConfirm.")
                    ]),
                    "session_id": .object(["type": .string("string")]),
                    "confirmation_token": .object(["type": .string("string")])
                ],
                required: ["snapshot_id", "element_id", "text"]
            ),
            annotations: .object([
                "readOnlyHint": .bool(false),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(true)
            ])
        ),
        MCPToolDefinition(
            name: scroll,
            description: "Scroll a window or element without moving the real mouse or changing focus. Drives the target's Accessibility scroll bars, so it works on fully background windows and never brings them forward.",
            inputSchema: objectSchema(
                properties: [
                    "snapshot_id": .object(["type": .string("string")]),
                    "element_id": .object([
                        "type": .string("string"),
                        "description": .string("Element to scroll; its scroll bars (or its window's) are driven via Accessibility.")
                    ]),
                    "direction": stringEnum(["up", "down", "left", "right"], defaultValue: "down"),
                    "pages": .object([
                        "type": .string("number"),
                        "default": .number(1),
                        "minimum": .number(0.05),
                        "description": .string("Scroll magnitude in pages.")
                    ]),
                    "target_pid": .object([
                        "type": .string("integer"),
                        "description": .string("Process id whose frontmost scroll area to scroll when no element is supplied; defaults to the frontmost application.")
                    ])
                ],
                required: ["direction"]
            ),
            annotations: .object([
                "readOnlyHint": .bool(false),
                "destructiveHint": .bool(false),
                "openWorldHint": .bool(true)
            ])
        )
    ]

    public static func definition(named name: String) -> MCPToolDefinition? {
        allDefinitions.first { $0.name == name }
    }

    private static func objectSchema(
        properties: MCPJSONObject,
        required: [String] = []
    ) -> MCPJSONValue {
        var schema: MCPJSONObject = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]

        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }

        return .object(schema)
    }

    private static func stringEnum(_ values: [String], defaultValue: String? = nil) -> MCPJSONValue {
        var schema: MCPJSONObject = [
            "type": .string("string"),
            "enum": .array(values.map { .string($0) })
        ]

        if let defaultValue {
            schema["default"] = .string(defaultValue)
        }

        return .object(schema)
    }
}
