import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

public enum PermissionState: String, Codable, Sendable {
    case granted
    case denied
    case unknown
}

public struct MacOSPermissionStatus: Codable, Sendable {
    public var accessibility: PermissionState
    public var screenCapture: PermissionState
    public var accessibilityPromptRequested: Bool
    public var screenCapturePreflightMethod: String
    public var bundleIdentifier: String?
    public var processIdentifier: Int32
    public var remediation: [String]

    public init(
        accessibility: PermissionState,
        screenCapture: PermissionState,
        accessibilityPromptRequested: Bool,
        screenCapturePreflightMethod: String,
        bundleIdentifier: String?,
        processIdentifier: Int32,
        remediation: [String]
    ) {
        self.accessibility = accessibility
        self.screenCapture = screenCapture
        self.accessibilityPromptRequested = accessibilityPromptRequested
        self.screenCapturePreflightMethod = screenCapturePreflightMethod
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.remediation = remediation
    }

    public var accessibilityTrusted: Bool {
        accessibility == .granted
    }

    public var screenCaptureTrusted: Bool {
        screenCapture == .granted
    }
}

public struct PermissionStatusReader: Sendable {
    public init() {}

    public func current(promptForAccessibility: Bool = false) -> MacOSPermissionStatus {
        let options = ["AXTrustedCheckOptionPrompt": promptForAccessibility] as CFDictionary
        let accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        let screenCaptureTrusted = CGPreflightScreenCaptureAccess()

        var remediation: [String] = []
        if !accessibilityTrusted {
            remediation.append("Grant Accessibility permission to this app in System Settings > Privacy & Security > Accessibility.")
        }
        if !screenCaptureTrusted {
            remediation.append("Grant Screen & System Audio Recording permission in System Settings > Privacy & Security.")
        }

        return MacOSPermissionStatus(
            accessibility: accessibilityTrusted ? .granted : .denied,
            screenCapture: screenCaptureTrusted ? .granted : .denied,
            accessibilityPromptRequested: promptForAccessibility,
            screenCapturePreflightMethod: "CGPreflightScreenCaptureAccess",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            remediation: remediation
        )
    }
}
