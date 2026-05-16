import Foundation

public enum VirtualCursorState: String, Codable, Sendable, CaseIterable, Hashable {
    case observing
    case aiming
    case pressing
    case typing
    case scrolling
    case dragging
    case blocked
    case handoff
}

public enum VirtualCursorFocusPolicy: String, Codable, Sendable, CaseIterable, Hashable {
    case noFocusChange = "no_focus_change"
    case temporaryHandoff = "temporary_handoff"
    case focusChangedIntentionally = "focus_changed_intentionally"
    case globalInput = "global_input"
    case failedBeforeFocusChange = "failed_before_focus_change"
}

public struct VirtualCursorPoint: Codable, Equatable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var coordinateSpace: String

    public init(
        x: Double,
        y: Double,
        coordinateSpace: String = "global_display_points"
    ) {
        self.x = x
        self.y = y
        self.coordinateSpace = coordinateSpace
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case coordinateSpace = "coordinate_space"
    }
}

public struct VirtualCursorFrame: Codable, Equatable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: VirtualCursorPoint {
        VirtualCursorPoint(x: x + width / 2, y: y + height / 2)
    }
}

public struct VirtualCursorPath: Codable, Equatable, Sendable, Hashable {
    public var points: [VirtualCursorPoint]

    public init(points: [VirtualCursorPoint]) {
        self.points = points
    }
}

public struct VirtualCursorTarget: Codable, Equatable, Sendable, Hashable {
    public var appBundleID: String?
    public var windowID: String?
    public var elementID: String?
    public var frame: VirtualCursorFrame?
    public var point: VirtualCursorPoint?
    public var path: VirtualCursorPath?

    public init(
        appBundleID: String? = nil,
        windowID: String? = nil,
        elementID: String? = nil,
        frame: VirtualCursorFrame? = nil,
        point: VirtualCursorPoint? = nil,
        path: VirtualCursorPath? = nil
    ) {
        self.appBundleID = appBundleID
        self.windowID = windowID
        self.elementID = elementID
        self.frame = frame
        self.point = point
        self.path = path
    }

    public var displayPoint: VirtualCursorPoint? {
        point ?? frame?.center ?? path?.points.last
    }

    private enum CodingKeys: String, CodingKey {
        case appBundleID = "app_bundle_id"
        case windowID = "window_id"
        case elementID = "element_id"
        case frame
        case point
        case path
    }
}

public struct VirtualCursorRecord: Codable, Equatable, Identifiable, Sendable, Hashable {
    public var cursorID: String
    public var sessionID: String
    public var taskLabel: String?
    public var state: VirtualCursorState
    public var target: VirtualCursorTarget
    public var visible: Bool
    public var lastToolCallID: String?
    public var lastExecutionLayer: String?
    public var realMouseMoved: Bool
    public var focusPolicy: VirtualCursorFocusPolicy
    public var updatedAt: Date

    public var id: String { cursorID }

    public init(
        cursorID: String,
        sessionID: String,
        taskLabel: String? = nil,
        state: VirtualCursorState,
        target: VirtualCursorTarget,
        visible: Bool = true,
        lastToolCallID: String? = nil,
        lastExecutionLayer: String? = nil,
        realMouseMoved: Bool = false,
        focusPolicy: VirtualCursorFocusPolicy = .noFocusChange,
        updatedAt: Date = .now
    ) {
        self.cursorID = cursorID
        self.sessionID = sessionID
        self.taskLabel = taskLabel
        self.state = state
        self.target = target
        self.visible = visible
        self.lastToolCallID = lastToolCallID
        self.lastExecutionLayer = lastExecutionLayer
        self.realMouseMoved = realMouseMoved
        self.focusPolicy = focusPolicy
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case cursorID = "cursor_id"
        case sessionID = "session_id"
        case taskLabel = "task_label"
        case state
        case target
        case visible
        case lastToolCallID = "last_tool_call_id"
        case lastExecutionLayer = "last_execution_layer"
        case realMouseMoved = "real_mouse_moved"
        case focusPolicy = "focus_policy"
        case updatedAt = "updated_at"
    }
}
