import Foundation

public enum ActionExecutionLayer: String, Codable, Sendable {
    case semanticAX = "semantic_ax"
    case semanticAXAtPosition = "semantic_ax_at_position"
    case appSpecificAPI = "app_specific_api"
    case quartzEvent = "quartz_event"
    case targetedQuartzEvent = "targeted_quartz_event"
    case temporaryFocusHandoff = "temporary_focus_handoff"
    case pasteboard
    case appLaunch = "app_launch"
    case diagnosticOnly = "diagnostic_only"
}

public enum ActionFocusPolicy: String, Codable, Sendable {
    case noFocusChange = "no_focus_change"
    case temporaryHandoff = "temporary_handoff"
    case focusChangedIntentionally = "focus_changed_intentionally"
    case globalInput = "global_input"
    case failedBeforeFocusChange = "failed_before_focus_change"
}

public enum ActionResultStatus: String, Codable, Sendable {
    case completed
    case failed
    case requiresConfirmation = "requires_confirmation"
}

public struct MacOSActionResult: Codable, Sendable {
    public var actionId: String
    public var requested: String
    public var status: ActionResultStatus
    public var executionLayer: ActionExecutionLayer
    public var focusPolicy: ActionFocusPolicy
    public var frontmostBefore: String?
    public var frontmostAfter: String?
    public var targetBundleIdentifier: String?
    public var targetProcessIdentifier: Int32?
    public var elementId: String?
    public var point: LMNHPoint?
    public var realMouseMoved: Bool
    public var fallbacksAttempted: [String]
    public var error: AXErrorInfo?
    public var warnings: [String]

    public init(
        actionId: String = "act_\(UUID().uuidString.prefix(8).lowercased())",
        requested: String,
        status: ActionResultStatus,
        executionLayer: ActionExecutionLayer,
        focusPolicy: ActionFocusPolicy,
        frontmostBefore: String?,
        frontmostAfter: String?,
        targetBundleIdentifier: String?,
        targetProcessIdentifier: Int32?,
        elementId: String?,
        point: LMNHPoint?,
        realMouseMoved: Bool = false,
        fallbacksAttempted: [String] = [],
        error: AXErrorInfo? = nil,
        warnings: [String] = []
    ) {
        self.actionId = actionId
        self.requested = requested
        self.status = status
        self.executionLayer = executionLayer
        self.focusPolicy = focusPolicy
        self.frontmostBefore = frontmostBefore
        self.frontmostAfter = frontmostAfter
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetProcessIdentifier = targetProcessIdentifier
        self.elementId = elementId
        self.point = point
        self.realMouseMoved = realMouseMoved
        self.fallbacksAttempted = fallbacksAttempted
        self.error = error
        self.warnings = warnings
    }
}
