import XCTest
@testable import LMNHCore

final class VirtualCursorControllerTests: XCTestCase {
    @MainActor
    func testSetCursorStoresVisibleRecordAndRenders() {
        let renderer = SpyCursorRenderer()
        let controller = VirtualCursorController(renderer: renderer)

        let record = controller.setCursor(
            cursorID: "cursor_1",
            sessionID: "session_abc",
            taskLabel: "Codex",
            state: .aiming,
            target: VirtualCursorTarget(
                appBundleID: "com.apple.TextEdit",
                windowID: "win_12",
                elementID: "el_button",
                frame: VirtualCursorFrame(x: 10, y: 20, width: 80, height: 30)
            ),
            lastToolCallID: "call_789",
            lastExecutionLayer: "semantic_ax"
        )

        XCTAssertTrue(record.visible)
        XCTAssertFalse(record.realMouseMoved)
        XCTAssertEqual(record.focusPolicy, .noFocusChange)
        XCTAssertEqual(record.target.displayPoint, VirtualCursorPoint(x: 50, y: 35))
        XCTAssertEqual(controller.listCursors().map(\.cursorID), ["cursor_1"])
        XCTAssertEqual(renderer.renderedCursorIDs, [["cursor_1"]])
    }

    @MainActor
    func testHideCursorKeepsHiddenRecordOutOfDefaultList() {
        let renderer = SpyCursorRenderer()
        let controller = VirtualCursorController(renderer: renderer)

        controller.setCursor(
            cursorID: "cursor_1",
            sessionID: "session_abc",
            state: .observing,
            target: VirtualCursorTarget(point: VirtualCursorPoint(x: 100, y: 200))
        )

        let hidden = controller.hideCursor(cursorID: "cursor_1")

        XCTAssertEqual(hidden?.visible, false)
        XCTAssertTrue(controller.listCursors().isEmpty)
        XCTAssertEqual(controller.listCursors(includeHidden: true).map(\.cursorID), ["cursor_1"])
        XCTAssertEqual(renderer.renderedCursorIDs, [["cursor_1"], []])
    }

    func testAllPlannedStatesAreRepresented() {
        XCTAssertEqual(
            Set(VirtualCursorState.allCases),
            [
                .observing,
                .aiming,
                .pressing,
                .typing,
                .scrolling,
                .dragging,
                .blocked,
                .handoff
            ]
        )
    }

    func testAllCursorThemesHavePresets() {
        for theme in VirtualCursorTheme.allCases {
            XCTAssertEqual(theme.defaultAppearance.theme, theme)
            XCTAssertFalse(theme.displayName.isEmpty)
        }
    }

    @MainActor
    func testBitmapCursorThemesLoadBundledFrames() {
        let themes: [VirtualCursorTheme] = [
            .customCurser,
            .flameBlack,
            .tardis,
            .crosshairGreen,
            .gunAdvanced,
            .shiningSword
        ]

        for theme in themes {
            let frame = VirtualCursorArtwork.bitmapFrame(for: theme, at: Date(timeIntervalSinceReferenceDate: 0))

            XCTAssertNotNil(frame, "\(theme.displayName) should load a bundled bitmap cursor frame")
        }
    }

    func testAppearanceDecodesLegacyConfigWithoutTheme() throws {
        let data = Data("""
        {"red":1.0,"green":0.18,"blue":0.62,"alpha":1.0,"scale":1.0,"animationDuration":0.42,"showLabels":true,"showPath":true}
        """.utf8)

        let appearance = try JSONDecoder().decode(VirtualCursorAppearance.self, from: data)

        XCTAssertEqual(appearance.theme, .pinkArrow)
        XCTAssertEqual(appearance.red, 1.0)
    }

    @MainActor
    func testRecordsEncodeWithMCPFriendlyKeys() throws {
        let record = VirtualCursorRecord(
            cursorID: "cursor_1",
            sessionID: "session_abc",
            state: .pressing,
            target: VirtualCursorTarget(
                appBundleID: "com.apple.calculator",
                windowID: "win_12",
                elementID: "el_button",
                point: VirtualCursorPoint(x: 842, y: 519)
            ),
            lastToolCallID: "call_789",
            lastExecutionLayer: "semantic_ax",
            focusPolicy: .noFocusChange
        )

        let data = try JSONEncoder().encode(record)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"cursor_id\""))
        XCTAssertTrue(json.contains("\"session_id\""))
        XCTAssertTrue(json.contains("\"coordinate_space\""))
        XCTAssertTrue(json.contains("\"focus_policy\":\"no_focus_change\""))
        XCTAssertTrue(json.contains("\"real_mouse_moved\":false"))
    }

    func testConvertsGlobalTopLeftPointToLocalAppKitPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

        XCTAssertEqual(
            VirtualCursorCoordinateConverter.localPoint(
                fromGlobalTopLeft: CGPoint(x: 538, y: 808),
                inScreenFrame: screen
            ),
            CGPoint(x: 538, y: 361)
        )
    }

    func testConvertsGlobalTopLeftRectToLocalAppKitRect() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

        XCTAssertEqual(
            VirtualCursorCoordinateConverter.localRect(
                fromGlobalTopLeft: CGRect(x: 514, y: 784, width: 48, height: 48),
                inScreenFrame: screen
            ),
            CGRect(x: 514, y: 337, width: 48, height: 48)
        )
    }

    func testScreenContainsGlobalTopLeftPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

        XCTAssertTrue(VirtualCursorCoordinateConverter.screenFrame(screen, containsGlobalTopLeft: CGPoint(x: 538, y: 808)))
        XCTAssertFalse(VirtualCursorCoordinateConverter.screenFrame(screen, containsGlobalTopLeft: CGPoint(x: 1900, y: 808)))
    }
}

@MainActor
private final class SpyCursorRenderer: VirtualCursorRendering {
    private(set) var renderedCursorIDs: [[String]] = []

    func render(cursors: [VirtualCursorRecord]) {
        renderedCursorIDs.append(cursors.map(\.cursorID))
    }

    func close() {}
}
