import Foundation

@MainActor
public protocol VirtualCursorRendering: AnyObject {
    func render(cursors: [VirtualCursorRecord])
    func close()
}

public enum VirtualCursorRenderMode: Sendable, Hashable {
    case automatic
    case appKit
    case headless
}

@MainActor
public final class NoOpVirtualCursorRenderer: VirtualCursorRendering {
    public init() {}

    public func render(cursors: [VirtualCursorRecord]) {}

    public func close() {}
}

@MainActor
public final class VirtualCursorController {
    private var cursors: [String: VirtualCursorRecord]
    private let renderer: any VirtualCursorRendering

    public init(
        mode: VirtualCursorRenderMode = .automatic,
        renderer: (any VirtualCursorRendering)? = nil
    ) {
        self.cursors = [:]

        if let renderer {
            self.renderer = renderer
            return
        }

        switch mode {
        case .automatic, .appKit:
            self.renderer = AppKitVirtualCursorRenderer.makeIfAvailable() ?? NoOpVirtualCursorRenderer()
        case .headless:
            self.renderer = NoOpVirtualCursorRenderer()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            renderer.close()
        }
    }

    @discardableResult
    public func setCursor(_ cursor: VirtualCursorRecord) -> VirtualCursorRecord {
        var visibleCursor = cursor
        visibleCursor.visible = true
        visibleCursor.updatedAt = .now
        cursors[visibleCursor.cursorID] = visibleCursor
        renderVisibleCursors()
        return visibleCursor
    }

    @discardableResult
    public func setCursor(
        cursorID: String,
        sessionID: String,
        taskLabel: String? = nil,
        state: VirtualCursorState,
        target: VirtualCursorTarget,
        lastToolCallID: String? = nil,
        lastExecutionLayer: String? = nil,
        realMouseMoved: Bool = false,
        focusPolicy: VirtualCursorFocusPolicy = .noFocusChange
    ) -> VirtualCursorRecord {
        setCursor(
            VirtualCursorRecord(
                cursorID: cursorID,
                sessionID: sessionID,
                taskLabel: taskLabel,
                state: state,
                target: target,
                visible: true,
                lastToolCallID: lastToolCallID,
                lastExecutionLayer: lastExecutionLayer,
                realMouseMoved: realMouseMoved,
                focusPolicy: focusPolicy
            )
        )
    }

    @discardableResult
    public func hideCursor(cursorID: String) -> VirtualCursorRecord? {
        guard var cursor = cursors[cursorID] else {
            return nil
        }

        cursor.visible = false
        cursor.updatedAt = .now
        cursors[cursorID] = cursor
        renderVisibleCursors()
        return cursor
    }

    public func listCursors(includeHidden: Bool = false) -> [VirtualCursorRecord] {
        cursors.values
            .filter { includeHidden || $0.visible }
            .sorted {
                if $0.sessionID == $1.sessionID {
                    return $0.cursorID < $1.cursorID
                }

                return $0.sessionID < $1.sessionID
            }
    }

    public func removeAllCursors() {
        cursors.removeAll()
        renderVisibleCursors()
    }

    private func renderVisibleCursors() {
        renderer.render(cursors: listCursors())
    }
}
