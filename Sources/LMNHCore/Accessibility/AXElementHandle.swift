import ApplicationServices
import Foundation

public final class AXElementHandle: @unchecked Sendable {
    public let raw: AXUIElement

    public init(_ raw: AXUIElement) {
        self.raw = raw
    }
}

public struct AXErrorInfo: Error, Codable, Sendable, Equatable {
    public var code: Int
    public var name: String

    public init(_ error: AXError) {
        self.code = Int(error.rawValue)
        self.name = Self.describe(error)
    }

    private static func describe(_ error: AXError) -> String {
        switch error {
        case .success:
            "success"
        case .failure:
            "failure"
        case .illegalArgument:
            "illegal_argument"
        case .invalidUIElement:
            "invalid_ui_element"
        case .invalidUIElementObserver:
            "invalid_ui_element_observer"
        case .cannotComplete:
            "cannot_complete"
        case .attributeUnsupported:
            "attribute_unsupported"
        case .actionUnsupported:
            "action_unsupported"
        case .notificationUnsupported:
            "notification_unsupported"
        case .notImplemented:
            "not_implemented"
        case .notificationAlreadyRegistered:
            "notification_already_registered"
        case .notificationNotRegistered:
            "notification_not_registered"
        case .apiDisabled:
            "api_disabled"
        case .noValue:
            "no_value"
        case .parameterizedAttributeUnsupported:
            "parameterized_attribute_unsupported"
        case .notEnoughPrecision:
            "not_enough_precision"
        @unknown default:
            "unknown"
        }
    }
}
