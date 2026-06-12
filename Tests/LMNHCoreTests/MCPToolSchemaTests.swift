import XCTest
@testable import LMNHCore

final class MCPToolSchemaTests: XCTestCase {
    func testTypeTextSchemaDeclaresFocuslessMutationModes() throws {
        let definition = try XCTUnwrap(LMNHMCPTools.definition(named: LMNHMCPTools.typeText))
        guard case let .object(schema) = definition.inputSchema,
              case let .object(properties)? = schema["properties"],
              case let .object(modeSchema)? = properties["mode"],
              case let .array(modeValues)? = modeSchema["enum"] else {
            return XCTFail("macos_type_text should expose a mode enum")
        }

        XCTAssertTrue(definition.description.contains("without focusing"))
        XCTAssertEqual(Set(modeValues.compactMap(\.stringValue)), ["replace", "append", "selection"])
        XCTAssertEqual(modeSchema["default"]?.stringValue, "replace")
    }

    func testTextEntryDiagnosticsEncodeFocuslessMetadata() throws {
        let diagnostics = TextEntryDiagnostics(
            method: "ax_set_value",
            requestedMode: "append",
            effectiveMode: "append",
            focusless: true,
            valueWasSettable: true,
            originalLength: 5,
            insertedLength: 3,
            resultingLength: 8,
            fallbackPolicy: "keyboard_and_paste_not_attempted_to_preserve_focus",
            settableAttributes: [AXNames.Attribute.value]
        )

        let value = try MCPJSONValue.encoded(diagnostics)
        guard case let .object(object) = value else {
            return XCTFail("diagnostics should encode as an object")
        }

        XCTAssertEqual(object["focusless"]?.boolValue, true)
        XCTAssertEqual(object["value_was_settable"]?.boolValue, true)
        XCTAssertEqual(object["fallback_policy"]?.stringValue, "keyboard_and_paste_not_attempted_to_preserve_focus")
    }

    func testScreenshotSchemaDeclaresCaptureTargetsAndDownscaling() throws {
        let definition = try XCTUnwrap(LMNHMCPTools.definition(named: LMNHMCPTools.getScreenshot))
        guard case let .object(schema) = definition.inputSchema,
              case let .object(properties)? = schema["properties"],
              case let .object(targetSchema)? = properties["target"],
              case let .array(targetValues)? = targetSchema["enum"],
              case let .object(formatSchema)? = properties["format"],
              case let .array(formatValues)? = formatSchema["enum"] else {
            return XCTFail("macos_get_screenshot should expose target and format enums")
        }

        XCTAssertFalse(definition.description.localizedCaseInsensitiveContains("not wired"))
        XCTAssertEqual(
            Set(targetValues.compactMap(\.stringValue)),
            ["frontmost_window", "window", "display", "element"]
        )
        XCTAssertEqual(Set(formatValues.compactMap(\.stringValue)), ["png", "jpeg"])
        XCTAssertNotNil(properties["max_width"])
        XCTAssertNotNil(properties["window_id"])
    }

    func testCompactTextEntryResultReportsSubmitOutcome() throws {
        let action = MacOSActionResult(
            requested: "focusless AXValue replace on el_1",
            status: .completed,
            executionLayer: .semanticAX,
            focusPolicy: .noFocusChange,
            frontmostBefore: nil,
            frontmostAfter: nil,
            targetBundleIdentifier: "com.example.app",
            targetProcessIdentifier: 1,
            elementId: "el_1",
            point: nil
        )
        var diagnostics = TextEntryDiagnostics(method: "ax_set_value", requestedMode: "replace", insertedLength: 4)
        diagnostics.submitAction = AXNames.Action.confirm
        diagnostics.submitStatus = "unsupported_element_has_no_axconfirm_action"

        let compact = CompactTextEntryResult(action: action, diagnostics: diagnostics, cursor: nil)
        XCTAssertEqual(compact.submit, "AXConfirm=unsupported_element_has_no_axconfirm_action")

        diagnostics.submitStatus = nil
        let noSubmit = CompactTextEntryResult(action: action, diagnostics: diagnostics, cursor: nil)
        XCTAssertNil(noSubmit.submit)
    }

    func testScreenshotServiceErrorReasonsAreMachineReadable() {
        XCTAssertEqual(ScreenshotServiceError.permissionDenied.reason, "screen_recording_permission_denied")
        XCTAssertEqual(ScreenshotServiceError.invalidTarget("bogus").reason, "invalid_target: bogus")
        XCTAssertTrue(ScreenshotServiceError.noWindowFound("w").reason.hasPrefix("no_window_found"))
    }
}
