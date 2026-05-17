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
}
