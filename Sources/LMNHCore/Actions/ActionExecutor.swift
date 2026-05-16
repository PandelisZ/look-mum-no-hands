import ApplicationServices
import AppKit
import Foundation

@MainActor
public final class ActionExecutor {
    private let elementRegistry: ElementRegistry
    private let axClient: AXClient
    private let safetyClassifier: SafetyClassifier

    public init(
        elementRegistry: ElementRegistry,
        axClient: AXClient = AXClient(),
        safetyClassifier: SafetyClassifier = SafetyClassifier()
    ) {
        self.elementRegistry = elementRegistry
        self.axClient = axClient
        self.safetyClassifier = safetyClassifier
    }

    public func performAction(
        snapshotId: String,
        elementId: String,
        action: String = AXNames.Action.press,
        confirmationToken: String? = nil
    ) -> MacOSActionResult {
        guard let registered = elementRegistry.resolve(snapshotId: snapshotId, elementId: elementId) else {
            return failedResult(
                requested: "perform \(action) on \(elementId)",
                layer: .semanticAX,
                elementId: elementId,
                error: nil,
                warning: "stale_element: element id is not in the registry"
            )
        }

        if registered.record.risk.requiresConfirmation && confirmationToken == nil {
            return requiresConfirmationResult(
                requested: "perform \(action) on \(elementId)",
                layer: .semanticAX,
                registered: registered,
                warning: registered.record.risk.reasons.joined(separator: ", ")
            )
        }

        let frontmostBefore = frontmostBundleIdentifier()
        let error = axClient.performAction(action, on: registered.handle)
        let frontmostAfter = frontmostBundleIdentifier()

        return MacOSActionResult(
            requested: "perform \(action) on \(elementId)",
            status: error == .success ? .completed : .failed,
            executionLayer: .semanticAX,
            focusPolicy: focusPolicy(error: error, before: frontmostBefore, after: frontmostAfter),
            frontmostBefore: frontmostBefore,
            frontmostAfter: frontmostAfter,
            targetBundleIdentifier: registered.record.bundleIdentifier,
            targetProcessIdentifier: registered.record.processIdentifier,
            elementId: elementId,
            point: registered.record.frame?.center,
            error: error == .success ? nil : AXErrorInfo(error),
            warnings: focusWarnings(error: error, before: frontmostBefore, after: frontmostAfter)
        )
    }

    public func press(snapshotId: String, elementId: String, confirmationToken: String? = nil) -> MacOSActionResult {
        performAction(
            snapshotId: snapshotId,
            elementId: elementId,
            action: AXNames.Action.press,
            confirmationToken: confirmationToken
        )
    }

    public func setValue(
        snapshotId: String,
        elementId: String,
        value: String,
        confirmationToken: String? = nil
    ) -> MacOSActionResult {
        guard let registered = elementRegistry.resolve(snapshotId: snapshotId, elementId: elementId) else {
            return failedResult(
                requested: "set AXValue on \(elementId)",
                layer: .semanticAX,
                elementId: elementId,
                error: nil,
                warning: "stale_element: element id is not in the registry"
            )
        }

        let textRisk = safetyClassifier.classifyText(value)
        let requiresConfirmation = registered.record.risk.requiresConfirmation || textRisk?.requiresConfirmation == true
        if requiresConfirmation && confirmationToken == nil {
            let reasons = (registered.record.risk.reasons + (textRisk?.reasons ?? [])).joined(separator: ", ")
            return requiresConfirmationResult(
                requested: "set AXValue on \(elementId)",
                layer: .semanticAX,
                registered: registered,
                warning: reasons.isEmpty ? "AXValue mutation requires confirmation" : reasons
            )
        }

        let frontmostBefore = frontmostBundleIdentifier()
        let error = axClient.setStringValue(value, on: registered.handle)
        let frontmostAfter = frontmostBundleIdentifier()

        return MacOSActionResult(
            requested: "set AXValue on \(elementId)",
            status: error == .success ? .completed : .failed,
            executionLayer: .semanticAX,
            focusPolicy: focusPolicy(error: error, before: frontmostBefore, after: frontmostAfter),
            frontmostBefore: frontmostBefore,
            frontmostAfter: frontmostAfter,
            targetBundleIdentifier: registered.record.bundleIdentifier,
            targetProcessIdentifier: registered.record.processIdentifier,
            elementId: elementId,
            point: registered.record.frame?.center,
            error: error == .success ? nil : AXErrorInfo(error),
            warnings: focusWarnings(error: error, before: frontmostBefore, after: frontmostAfter)
        )
    }

    public func click(
        snapshotId: String? = nil,
        elementId: String? = nil,
        point: LMNHPoint? = nil,
        targetProcessIdentifier: Int32? = nil,
        confirmationToken: String? = nil
    ) -> MacOSActionResult {
        if let snapshotId, let elementId {
            return press(snapshotId: snapshotId, elementId: elementId, confirmationToken: confirmationToken)
        }

        guard let point else {
            return failedResult(
                requested: "click",
                layer: .semanticAXAtPosition,
                elementId: nil,
                error: nil,
                warning: "click requires either an element id or a global point"
            )
        }

        let frontmostBefore = frontmostBundleIdentifier()
        let result = axClient.elementAtPosition(point.cgPoint, processIdentifier: targetProcessIdentifier)

        switch result {
        case .success(let element):
            let pressError = axClient.performAction(AXNames.Action.press, on: element)
            let frontmostAfter = frontmostBundleIdentifier()
            return MacOSActionResult(
                requested: "click at \(point.x),\(point.y)",
                status: pressError == .success ? .completed : .failed,
                executionLayer: .semanticAXAtPosition,
                focusPolicy: focusPolicy(error: pressError, before: frontmostBefore, after: frontmostAfter),
                frontmostBefore: frontmostBefore,
                frontmostAfter: frontmostAfter,
                targetBundleIdentifier: nil,
                targetProcessIdentifier: targetProcessIdentifier,
                elementId: nil,
                point: point,
                realMouseMoved: false,
                fallbacksAttempted: ["AXUIElementCopyElementAtPosition"],
                error: pressError == .success ? nil : AXErrorInfo(pressError),
                warnings: focusWarnings(error: pressError, before: frontmostBefore, after: frontmostAfter)
            )

        case .failure(let error):
            let frontmostAfter = frontmostBundleIdentifier()
            return MacOSActionResult(
                requested: "click at \(point.x),\(point.y)",
                status: .failed,
                executionLayer: .semanticAXAtPosition,
                focusPolicy: .failedBeforeFocusChange,
                frontmostBefore: frontmostBefore,
                frontmostAfter: frontmostAfter,
                targetBundleIdentifier: nil,
                targetProcessIdentifier: targetProcessIdentifier,
                elementId: nil,
                point: point,
                realMouseMoved: false,
                fallbacksAttempted: ["AXUIElementCopyElementAtPosition"],
                error: error
            )
        }
    }

    private func requiresConfirmationResult(
        requested: String,
        layer: ActionExecutionLayer,
        registered: RegisteredElement,
        warning: String
    ) -> MacOSActionResult {
        MacOSActionResult(
            requested: requested,
            status: .requiresConfirmation,
            executionLayer: layer,
            focusPolicy: .failedBeforeFocusChange,
            frontmostBefore: frontmostBundleIdentifier(),
            frontmostAfter: frontmostBundleIdentifier(),
            targetBundleIdentifier: registered.record.bundleIdentifier,
            targetProcessIdentifier: registered.record.processIdentifier,
            elementId: registered.record.id,
            point: registered.record.frame?.center,
            warnings: [warning].filter { !$0.isEmpty }
        )
    }

    private func failedResult(
        requested: String,
        layer: ActionExecutionLayer,
        elementId: String?,
        error: AXErrorInfo?,
        warning: String
    ) -> MacOSActionResult {
        MacOSActionResult(
            requested: requested,
            status: .failed,
            executionLayer: layer,
            focusPolicy: .failedBeforeFocusChange,
            frontmostBefore: frontmostBundleIdentifier(),
            frontmostAfter: frontmostBundleIdentifier(),
            targetBundleIdentifier: nil,
            targetProcessIdentifier: nil,
            elementId: elementId,
            point: nil,
            error: error,
            warnings: [warning]
        )
    }

    private func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func focusPolicy(error: AXError, before: String?, after: String?) -> ActionFocusPolicy {
        guard error == .success else {
            return .failedBeforeFocusChange
        }

        if before != after {
            return .focusChangedIntentionally
        }

        return .noFocusChange
    }

    private func focusWarnings(error: AXError, before: String?, after: String?) -> [String] {
        guard error == .success, before != after else {
            return []
        }

        return ["frontmost_app_changed_during_semantic_action: \(before ?? "<none>") -> \(after ?? "<none>")"]
    }
}
