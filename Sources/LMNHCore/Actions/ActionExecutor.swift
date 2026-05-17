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
        setText(
            snapshotId: snapshotId,
            elementId: elementId,
            text: value,
            mode: .replace,
            confirmationToken: confirmationToken
        ).action
    }

    public func setText(
        snapshotId: String,
        elementId: String,
        text: String,
        mode: TextEntryMutationMode,
        confirmationToken: String? = nil
    ) -> TextEntryResult {
        let requested = "focusless AXValue \(mode.rawValue) on \(elementId)"
        var diagnostics = TextEntryDiagnostics(
            method: "ax_set_value",
            requestedMode: mode.rawValue,
            insertedLength: text.utf16.count,
            fallbackPolicy: "keyboard_and_paste_not_attempted_to_preserve_focus"
        )

        guard let registered = elementRegistry.resolve(snapshotId: snapshotId, elementId: elementId) else {
            diagnostics.failureReason = "stale_element"
            return TextEntryResult(action: failedResult(
                requested: requested,
                layer: .semanticAX,
                elementId: elementId,
                error: nil,
                warning: "stale_element: element id is not in the registry"
            ), diagnostics: diagnostics)
        }

        diagnostics.role = registered.record.role
        diagnostics.settableAttributes = axClient.settableAttributes(of: registered.handle)
        diagnostics.valueWasSettable = diagnostics.settableAttributes.contains(AXNames.Attribute.value)
        diagnostics.originalLength = axClient.stringAttribute(AXNames.Attribute.value, of: registered.handle)?.utf16.count

        guard registered.record.enabled != false else {
            diagnostics.failureReason = "target_disabled"
            return TextEntryResult(action: failedResult(
                requested: requested,
                layer: .semanticAX,
                elementId: elementId,
                error: nil,
                warning: "target_disabled: AXValue mutation requires an enabled input element"
            ), diagnostics: diagnostics)
        }

        guard diagnostics.valueWasSettable else {
            diagnostics.failureReason = "ax_value_not_settable"
            return TextEntryResult(action: failedResult(
                requested: requested,
                layer: .semanticAX,
                elementId: elementId,
                error: nil,
                warning: "ax_value_not_settable: \(AXNames.Attribute.value) is not settable on this element"
            ), diagnostics: diagnostics)
        }

        switch makeTextMutation(mode: mode, text: text, registered: registered) {
        case .failure(let reason, let selectedRange):
            diagnostics.failureReason = reason
            diagnostics.selectedRange = selectedRange
            return TextEntryResult(action: failedResult(
                requested: requested,
                layer: .semanticAX,
                elementId: elementId,
                error: nil,
                warning: reason
            ), diagnostics: diagnostics)

        case .success(let finalValue, let effectiveMode, let selectedRange):
            diagnostics.effectiveMode = effectiveMode.rawValue
            diagnostics.selectedRange = selectedRange
            diagnostics.resultingLength = finalValue.utf16.count

            let textRisk = safetyClassifier.classifyText(finalValue)
            let requiresConfirmation = registered.record.risk.requiresConfirmation || textRisk?.requiresConfirmation == true
            if requiresConfirmation && confirmationToken == nil {
                let reasons = (registered.record.risk.reasons + (textRisk?.reasons ?? [])).joined(separator: ", ")
                diagnostics.failureReason = "requires_confirmation"
                return TextEntryResult(action: requiresConfirmationResult(
                    requested: requested,
                    layer: .semanticAX,
                    registered: registered,
                    warning: reasons.isEmpty ? "AXValue mutation requires confirmation" : reasons
                ), diagnostics: diagnostics)
            }

            let frontmostBefore = frontmostBundleIdentifier()
            let error = axClient.setStringValue(finalValue, on: registered.handle)
            if error == .success {
                updateSelectedRangeAfterMutationIfPossible(
                    mode: effectiveMode,
                    insertedLength: text.utf16.count,
                    selectedRange: selectedRange,
                    registered: registered
                )
            }
            let frontmostAfter = frontmostBundleIdentifier()
            diagnostics.failureReason = error == .success ? nil : "ax_set_value_failed"

            return TextEntryResult(
                action: MacOSActionResult(
                    requested: requested,
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
                ),
                diagnostics: diagnostics
            )
        }
    }

    private enum TextMutation {
        case success(finalValue: String, effectiveMode: TextEntryMutationMode, selectedRange: String?)
        case failure(reason: String, selectedRange: String?)
    }

    private func makeTextMutation(
        mode: TextEntryMutationMode,
        text: String,
        registered: RegisteredElement
    ) -> TextMutation {
        switch mode {
        case .replace:
            return .success(finalValue: text, effectiveMode: .replace, selectedRange: nil)
        case .append:
            guard let currentValue = axClient.stringAttribute(AXNames.Attribute.value, of: registered.handle) else {
                return .failure(reason: "ax_value_unavailable_for_append", selectedRange: nil)
            }
            return .success(finalValue: currentValue + text, effectiveMode: .append, selectedRange: nil)
        case .selection:
            guard let currentValue = axClient.stringAttribute(AXNames.Attribute.value, of: registered.handle) else {
                return .failure(reason: "ax_value_unavailable_for_selection_replacement", selectedRange: nil)
            }
            guard let selectedRange = axClient.rangeAttribute(AXNames.Attribute.selectedTextRange, of: registered.handle) else {
                return .failure(reason: "selected_text_range_unavailable", selectedRange: nil)
            }
            let nsValue = currentValue as NSString
            guard selectedRange.location >= 0,
                  selectedRange.length >= 0,
                  selectedRange.location <= nsValue.length,
                  selectedRange.location + selectedRange.length <= nsValue.length else {
                return .failure(
                    reason: "selected_text_range_out_of_bounds",
                    selectedRange: "\(selectedRange.location):\(selectedRange.length)"
                )
            }
            let finalValue = nsValue.replacingCharacters(
                in: NSRange(location: selectedRange.location, length: selectedRange.length),
                with: text
            )
            return .success(
                finalValue: finalValue,
                effectiveMode: .selection,
                selectedRange: "\(selectedRange.location):\(selectedRange.length)"
            )
        }
    }

    private func updateSelectedRangeAfterMutationIfPossible(
        mode: TextEntryMutationMode,
        insertedLength: Int,
        selectedRange: String?,
        registered: RegisteredElement
    ) {
        guard mode == .selection,
              let selectedRange,
              axClient.isAttributeSettable(AXNames.Attribute.selectedTextRange, of: registered.handle) else {
            return
        }

        let parts = selectedRange.split(separator: ":", maxSplits: 1).compactMap { Int($0) }
        guard parts.count == 2 else {
            return
        }

        _ = axClient.setRangeValue(
            CFRange(location: parts[0] + insertedLength, length: 0),
            on: registered.handle
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
