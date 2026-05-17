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
    static let inactivityTimeout: TimeInterval = 10

    private var cursors: [String: VirtualCursorRecord]
    private let renderer: any VirtualCursorRendering
    private var inactivityTimer: Timer?

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
            inactivityTimer?.invalidate()
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
        scheduleInactivityTimeout()
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
        scheduleInactivityTimeout()
        return cursor
    }

    public func listCursors(includeHidden: Bool = false) -> [VirtualCursorRecord] {
        expireInactiveCursors()
        return sortedCursors(includeHidden: includeHidden)
    }

    private func sortedCursors(includeHidden: Bool = false) -> [VirtualCursorRecord] {
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
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        renderVisibleCursors()
    }

    private func renderVisibleCursors() {
        renderer.render(cursors: sortedCursors())
    }

    func expireInactiveCursors(
        now: Date = .now,
        renderIfChanged: Bool = true
    ) {
        var changed = false

        for (cursorID, cursor) in cursors where cursor.visible {
            guard now.timeIntervalSince(cursor.updatedAt) >= Self.inactivityTimeout else {
                continue
            }

            var expired = cursor
            expired.visible = false
            expired.updatedAt = now
            cursors[cursorID] = expired
            changed = true
        }

        if changed, renderIfChanged {
            renderVisibleCursors()
        }

        scheduleInactivityTimeout(now: now)
    }

    private func scheduleInactivityTimeout(now: Date = .now) {
        inactivityTimer?.invalidate()
        inactivityTimer = nil

        let nextDeadline = cursors.values
            .filter(\.visible)
            .map { $0.updatedAt.addingTimeInterval(Self.inactivityTimeout) }
            .min()

        guard let nextDeadline else {
            return
        }

        let interval = max(nextDeadline.timeIntervalSince(now), 0.05)
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.expireInactiveCursors()
            }
        }
        RunLoop.main.add(inactivityTimer!, forMode: .common)
    }
}
