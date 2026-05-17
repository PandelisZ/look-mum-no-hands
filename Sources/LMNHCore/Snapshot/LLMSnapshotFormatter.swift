import Foundation

public struct LLMSnapshot: Codable, Sendable {
    public var id: String
    public var app: CompactApp?
    public var frontmostApp: CompactApp?
    public var window: CompactWindow?
    public var elements: [CompactElement]
    public var virtualCursors: [VirtualCursorRecord]
    public var warnings: [String]
    public var text: String

    private enum CodingKeys: String, CodingKey {
        case id
        case app
        case frontmostApp = "frontmost_app"
        case window
        case elements
        case virtualCursors = "virtual_cursors"
        case warnings
        case text
    }
}

public struct CompactApp: Codable, Sendable {
    public var name: String
    public var bundleIdentifier: String?
    public var processIdentifier: Int32
    public var isFrontmost: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier = "bundle_id"
        case processIdentifier = "pid"
        case isFrontmost = "frontmost"
    }
}

public struct CompactWindow: Codable, Sendable {
    public var id: UInt32?
    public var title: String?
    public var frame: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case frame
    }
}

public struct CompactElement: Codable, Sendable {
    public var id: String
    public var role: String
    public var label: String?
    public var value: String?
    public var action: String?
    public var frame: String?
    public var state: [String]
    public var risk: String?
}

public enum LLMSnapshotFormatter {
    public static func format(_ snapshot: MacOSSnapshot, maxElements: Int = 120) -> LLMSnapshot {
        let targetWindow = primaryWindow(for: snapshot)
        let compactElements = filteredElements(snapshot.accessibilityTree, targetWindow: targetWindow)
            .prefix(maxElements)
            .map(compactElement)
        let warnings = warnings(snapshot: snapshot, returnedCount: compactElements.count)
        let compact = LLMSnapshot(
            id: snapshot.id,
            app: snapshot.targetApplication.map(compactApp),
            frontmostApp: snapshot.frontmostApplication.map(compactApp),
            window: targetWindow.map(compactWindow),
            elements: Array(compactElements),
            virtualCursors: snapshot.virtualCursors,
            warnings: warnings,
            text: ""
        )
        var withText = compact
        withText.text = renderText(withText)
        return withText
    }

    private static func compactApp(_ app: RunningApplicationInfo) -> CompactApp {
        CompactApp(
            name: app.localizedName,
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            isFrontmost: app.isFrontmost
        )
    }

    private static func compactWindow(_ window: MacOSWindowInfo) -> CompactWindow {
        CompactWindow(
            id: window.id,
            title: window.title,
            frame: window.bounds.map(formatFrame)
        )
    }

    private static func primaryWindow(for snapshot: MacOSSnapshot) -> MacOSWindowInfo? {
        guard let targetPID = snapshot.targetApplication?.processIdentifier else {
            return nil
        }

        let candidates = snapshot.windows.filter { window in
            window.ownerPID == targetPID
                && window.layer == 0
                && window.isOnscreen
                && window.alpha > 0
                && window.bounds?.isUsableFrame == true
        }

        if let focusedWindowId = snapshot.focusedWindowElementId,
           let focusedWindow = snapshot.accessibilityTree.first(where: { $0.id == focusedWindowId }),
           let focusedFrame = focusedWindow.frame {
            return candidates.max { left, right in
                overlapArea(left.bounds, focusedFrame) < overlapArea(right.bounds, focusedFrame)
            }
        }

        return candidates.max { left, right in
            area(left.bounds) < area(right.bounds)
        }
    }

    private static func filteredElements(
        _ records: [AccessibilityElementRecord],
        targetWindow: MacOSWindowInfo?
    ) -> [AccessibilityElementRecord] {
        records.filter { record in
            guard shouldInclude(record) else {
                return false
            }

            guard let targetFrame = targetWindow?.bounds else {
                return record.visible
            }

            guard let frame = record.frame else {
                return record.role == AXNames.Role.window
            }

            return overlapArea(frame, targetFrame) > 0 || record.focused == true
        }
        .sorted { left, right in
            switch (left.frame, right.frame) {
            case let (leftFrame?, rightFrame?):
                if leftFrame.y == rightFrame.y {
                    return leftFrame.x < rightFrame.x
                }
                return leftFrame.y < rightFrame.y
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.id < right.id
            }
        }
    }

    private static func shouldInclude(_ record: AccessibilityElementRecord) -> Bool {
        if record.role == AXNames.Role.window {
            return record.visible
        }

        if isMenuChrome(record) {
            return false
        }

        if record.visible == false {
            return false
        }

        if record.frame?.isUsableFrame == false {
            return false
        }

        if record.defaultAction != nil || !record.actions.isEmpty || record.focused == true {
            return true
        }

        if record.valuePreview?.isEmpty == false || record.label?.isEmpty == false {
            return true
        }

        return false
    }

    private static func isMenuChrome(_ record: AccessibilityElementRecord) -> Bool {
        switch record.role {
        case "AXMenuBar", "AXMenuBarItem", "AXMenu", "AXMenuItem":
            return true
        default:
            return false
        }
    }

    private static func compactElement(_ record: AccessibilityElementRecord) -> CompactElement {
        var state: [String] = []
        if record.enabled == false { state.append("disabled") }
        if record.focused == true { state.append("focused") }
        if record.selected == true { state.append("selected") }
        if !record.visible { state.append("hidden") }
        if state.isEmpty { state.append("normal") }

        return CompactElement(
            id: record.id,
            role: compactRole(record.role),
            label: firstNonEmpty(record.label, record.title, record.description),
            value: record.valuePreview,
            action: record.defaultAction ?? firstAction(record.actions),
            frame: record.frame.map(formatFrame),
            state: state,
            risk: record.risk.requiresConfirmation ? record.risk.category.rawValue : nil
        )
    }

    private static func compactRole(_ role: String?) -> String {
        (role ?? "AXElement")
            .replacingOccurrences(of: "AX", with: "")
            .lowercased()
    }

    private static func firstAction(_ actions: [String]) -> String? {
        if actions.contains(AXNames.Action.press) { return "press" }
        if actions.contains(AXNames.Action.showMenu) { return "show_menu" }
        if actions.contains(AXNames.Action.raise) { return "raise" }
        return actions.first
    }

    private static func renderText(_ snapshot: LLMSnapshot) -> String {
        var lines: [String] = []
        lines.append("<macos_snapshot id=\"\(snapshot.id)\">")
        if let app = snapshot.app {
            lines.append("  <app name=\"\(xml(app.name))\" bundle=\"\(xml(app.bundleIdentifier ?? ""))\" pid=\"\(app.processIdentifier)\" frontmost=\"\(app.isFrontmost)\" />")
        }
        if let frontmost = snapshot.frontmostApp, frontmost.bundleIdentifier != snapshot.app?.bundleIdentifier {
            lines.append("  <frontmost name=\"\(xml(frontmost.name))\" bundle=\"\(xml(frontmost.bundleIdentifier ?? ""))\" />")
        }
        if let window = snapshot.window {
            lines.append("  <window title=\"\(xml(window.title ?? ""))\" frame=\"\(window.frame ?? "")\" />")
        }
        if !snapshot.warnings.isEmpty {
            lines.append("  <warnings>")
            for warning in snapshot.warnings {
                lines.append("    - \(warning)")
            }
            lines.append("  </warnings>")
        }
        lines.append("  <elements>")
        for element in snapshot.elements {
            var attrs = [
                "id=\"\(element.id)\"",
                "role=\"\(xml(element.role))\""
            ]
            if let label = element.label { attrs.append("label=\"\(xml(label))\"") }
            if let value = element.value { attrs.append("value=\"\(xml(value))\"") }
            if let action = element.action { attrs.append("action=\"\(xml(action))\"") }
            if let frame = element.frame { attrs.append("frame=\"\(frame)\"") }
            if element.state != ["normal"] { attrs.append("state=\"\(element.state.joined(separator: ","))\"") }
            if let risk = element.risk { attrs.append("risk=\"\(xml(risk))\"") }
            lines.append("    <el \(attrs.joined(separator: " ")) />")
        }
        lines.append("  </elements>")
        lines.append("</macos_snapshot>")
        return lines.joined(separator: "\n")
    }

    private static func warnings(snapshot: MacOSSnapshot, returnedCount: Int) -> [String] {
        var warnings = snapshot.warnings
        if returnedCount < snapshot.accessibilityTree.count {
            warnings.append("Returned \(returnedCount) compact elements from \(snapshot.accessibilityTree.count) raw AX records; menu/off-window/chrome nodes were omitted.")
        }
        return warnings
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func formatFrame(_ rect: LMNHRect) -> String {
        "\(Int(rect.x)),\(Int(rect.y)) \(Int(rect.width))x\(Int(rect.height))"
    }

    private static func xml(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func area(_ rect: LMNHRect?) -> Double {
        guard let rect else { return 0 }
        return rect.width * rect.height
    }

    private static func overlapArea(_ lhs: LMNHRect?, _ rhs: LMNHRect?) -> Double {
        guard let lhs, let rhs else { return 0 }
        let xOverlap = max(0, min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x))
        let yOverlap = max(0, min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y))
        return xOverlap * yOverlap
    }
}
