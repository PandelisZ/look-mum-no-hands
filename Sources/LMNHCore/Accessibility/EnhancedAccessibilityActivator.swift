import ApplicationServices
import Foundation

/// Many Chromium- and Electron-based apps (Chrome, Slack, VS Code, Discord, ...) keep
/// their accessibility tree collapsed until a client sets `AXManualAccessibility` or
/// `AXEnhancedUserInterface` on the app element. This activator sets those attributes so
/// `macos_snapshot` can see real UI instead of an empty web view.
public final class EnhancedAccessibilityActivator: @unchecked Sendable {
    public static let shared = EnhancedAccessibilityActivator()

    private let lock = NSLock()
    private var activatedProcessIdentifiers: Set<Int32> = []

    public init() {}

    /// Sets the enhanced-accessibility attributes on the app element.
    /// Returns true the first time a given process is activated, so callers can choose to
    /// wait briefly for the tree to populate before reading it.
    @discardableResult
    public func activateIfNeeded(processIdentifier: Int32, applicationElement: AXElementHandle) -> Bool {
        lock.lock()
        let firstActivation = !activatedProcessIdentifiers.contains(processIdentifier)
        lock.unlock()

        var accepted = false
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            let result = AXUIElementSetAttributeValue(
                applicationElement.raw,
                attribute as CFString,
                kCFBooleanTrue
            )
            accepted = accepted || result == .success
        }

        guard accepted, firstActivation else {
            return false
        }

        lock.lock()
        activatedProcessIdentifiers.insert(processIdentifier)
        lock.unlock()
        return true
    }
}
