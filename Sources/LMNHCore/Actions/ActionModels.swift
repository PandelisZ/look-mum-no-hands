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

public enum TextEntryMutationMode: String, Codable, Sendable {
    case replace
    case append
    case selection
}

public struct TextEntryDiagnostics: Codable, Sendable {
    public var method: String
    public var requestedMode: String
    public var effectiveMode: String?
    public var focusless: Bool
    public var valueAttribute: String
    public var valueWasSettable: Bool
    public var selectedRange: String?
    public var originalLength: Int?
    public var insertedLength: Int
    public var resultingLength: Int?
    public var fallbackPolicy: String
    public var failureReason: String?
    public var role: String?
    public var settableAttributes: [String]
    public var submitAction: String?
    public var submitStatus: String?

    public init(
        method: String,
        requestedMode: String,
        effectiveMode: String? = nil,
        focusless: Bool = true,
        valueAttribute: String = AXNames.Attribute.value,
        valueWasSettable: Bool = false,
        selectedRange: String? = nil,
        originalLength: Int? = nil,
        insertedLength: Int,
        resultingLength: Int? = nil,
        fallbackPolicy: String = "keyboard_and_paste_not_attempted",
        failureReason: String? = nil,
        role: String? = nil,
        settableAttributes: [String] = [],
        submitAction: String? = nil,
        submitStatus: String? = nil
    ) {
        self.method = method
        self.requestedMode = requestedMode
        self.effectiveMode = effectiveMode
        self.focusless = focusless
        self.valueAttribute = valueAttribute
        self.valueWasSettable = valueWasSettable
        self.selectedRange = selectedRange
        self.originalLength = originalLength
        self.insertedLength = insertedLength
        self.resultingLength = resultingLength
        self.fallbackPolicy = fallbackPolicy
        self.failureReason = failureReason
        self.role = role
        self.settableAttributes = settableAttributes
        self.submitAction = submitAction
        self.submitStatus = submitStatus
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case requestedMode = "requested_mode"
        case effectiveMode = "effective_mode"
        case focusless
        case valueAttribute = "value_attribute"
        case valueWasSettable = "value_was_settable"
        case selectedRange = "selected_range"
        case originalLength = "original_length"
        case insertedLength = "inserted_length"
        case resultingLength = "resulting_length"
        case fallbackPolicy = "fallback_policy"
        case failureReason = "failure_reason"
        case role
        case settableAttributes = "settable_attributes"
        case submitAction = "submit_action"
        case submitStatus = "submit_status"
    }
}

public struct TextEntryResult: Codable, Sendable {
    public var action: MacOSActionResult
    public var diagnostics: TextEntryDiagnostics

    public init(action: MacOSActionResult, diagnostics: TextEntryDiagnostics) {
        self.action = action
        self.diagnostics = diagnostics
    }
}

public struct CompactPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(_ point: LMNHPoint) {
        self.x = point.x
        self.y = point.y
    }
}

public struct CompactActionResult: Codable, Sendable {
    public var id: String
    public var status: String
    public var layer: String
    public var focus: String
    public var realMouseMoved: Bool
    public var target: String?
    public var point: CompactPoint?
    public var cursor: String?
    public var warning: String?
    public var error: String?
    public var text: String

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case layer
        case focus
        case realMouseMoved = "real_mouse_moved"
        case target
        case point
        case cursor
        case warning
        case error
        case text
    }

    public init(action: MacOSActionResult, cursor: VirtualCursorRecord? = nil, text: String? = nil) {
        self.id = action.actionId
        self.status = action.status.rawValue
        self.layer = action.executionLayer.rawValue
        self.focus = action.focusPolicy.rawValue
        self.realMouseMoved = action.realMouseMoved
        self.target = action.elementId ?? action.targetBundleIdentifier
        self.point = action.point.map(CompactPoint.init)
        self.cursor = cursor.map { "\($0.state.rawValue)@\($0.cursorID)" }
        self.warning = action.warnings.first
        self.error = action.error.map { "\($0.name)(\($0.code))" }
        self.text = text ?? Self.defaultText(action: action)
    }

    private static func defaultText(action: MacOSActionResult) -> String {
        var parts = [
            "status=\(action.status.rawValue)",
            "layer=\(action.executionLayer.rawValue)",
            "focus=\(action.focusPolicy.rawValue)",
            "mouse_moved=\(action.realMouseMoved)"
        ]
        if let elementId = action.elementId {
            parts.append("target=\(elementId)")
        } else if let point = action.point {
            parts.append("point=\(Int(point.x)),\(Int(point.y))")
        }
        if let warning = action.warnings.first {
            parts.append("warning=\(warning)")
        }
        return parts.joined(separator: " ")
    }
}

public struct CompactTextEntryResult: Codable, Sendable {
    public var action: CompactActionResult
    public var mode: String
    public var method: String
    public var focusless: Bool
    public var insertedLength: Int
    public var resultingLength: Int?
    public var fallbackPolicy: String
    public var failureReason: String?
    public var submit: String?

    private enum CodingKeys: String, CodingKey {
        case action
        case mode
        case method
        case focusless
        case insertedLength = "inserted_length"
        case resultingLength = "resulting_length"
        case fallbackPolicy = "fallback_policy"
        case failureReason = "failure_reason"
        case submit
    }

    public init(action: MacOSActionResult, diagnostics: TextEntryDiagnostics, cursor: VirtualCursorRecord?) {
        self.action = CompactActionResult(action: action, cursor: cursor)
        self.mode = diagnostics.effectiveMode ?? diagnostics.requestedMode
        self.method = diagnostics.method
        self.focusless = diagnostics.focusless
        self.insertedLength = diagnostics.insertedLength
        self.resultingLength = diagnostics.resultingLength
        self.fallbackPolicy = diagnostics.fallbackPolicy
        self.failureReason = diagnostics.failureReason
        self.submit = diagnostics.submitStatus.map { status in
            diagnostics.submitAction.map { "\($0)=\(status)" } ?? status
        }
    }
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
