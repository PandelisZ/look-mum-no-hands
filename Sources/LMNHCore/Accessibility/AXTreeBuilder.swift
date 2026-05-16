import ApplicationServices
import CoreGraphics
import Foundation

public struct AXTreeBuildOptions: Sendable {
    public var mode: SnapshotMode
    public var maxDepth: Int
    public var maxNodes: Int

    public init(mode: SnapshotMode = .standard, maxDepth: Int = 8, maxNodes: Int = 750) {
        self.mode = mode
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }
}

public struct AXTreeBuildResult: Sendable {
    public var records: [AccessibilityElementRecord]
    public var registryEntries: [RegisteredElement]
    public var warnings: [String]

    public init(records: [AccessibilityElementRecord], registryEntries: [RegisteredElement], warnings: [String]) {
        self.records = records
        self.registryEntries = registryEntries
        self.warnings = warnings
    }
}

public struct AXTreeBuilder: Sendable {
    private let client: AXClient
    private let redactor: Redactor
    private let safetyClassifier: SafetyClassifier

    public init(
        client: AXClient = AXClient(),
        redactor: Redactor = Redactor(),
        safetyClassifier: SafetyClassifier = SafetyClassifier()
    ) {
        self.client = client
        self.redactor = redactor
        self.safetyClassifier = safetyClassifier
    }

    public func buildApplicationTree(
        root: AXElementHandle,
        snapshotId: String,
        processIdentifier: Int32,
        bundleIdentifier: String?,
        appName: String?,
        options: AXTreeBuildOptions = AXTreeBuildOptions()
    ) -> AXTreeBuildResult {
        var context = BuildContext(
            snapshotId: snapshotId,
            shortSnapshotId: Self.shortSnapshotId(snapshotId),
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            options: options
        )

        traverse(root, parentId: nil, depth: 0, path: [], siblingIndex: 0, context: &context)

        if context.nodeIndex >= options.maxNodes {
            context.warnings.append("AX tree truncated at \(options.maxNodes) nodes.")
        }

        return AXTreeBuildResult(
            records: context.records,
            registryEntries: context.registryEntries,
            warnings: context.warnings
        )
    }

    private func traverse(
        _ element: AXElementHandle,
        parentId: String?,
        depth: Int,
        path: [String],
        siblingIndex: Int,
        context: inout BuildContext
    ) {
        guard depth <= context.options.maxDepth, context.nodeIndex < context.options.maxNodes else {
            return
        }

        let rawIdentity = CFHash(element.raw)
        guard context.visited.insert(rawIdentity).inserted else {
            return
        }

        let role = client.stringAttribute(AXNames.Attribute.role, of: element)
        let subrole = client.stringAttribute(AXNames.Attribute.subrole, of: element)
        let roleDescription = client.stringAttribute(AXNames.Attribute.roleDescription, of: element)
        let title = client.stringAttribute(AXNames.Attribute.title, of: element)
        let description = client.stringAttribute(AXNames.Attribute.description, of: element)
        let help = client.stringAttribute(AXNames.Attribute.help, of: element)
        let placeholder = client.stringAttribute(AXNames.Attribute.placeholderValue, of: element)
        let enabled = client.boolAttribute(AXNames.Attribute.enabled, of: element)
        let focused = client.boolAttribute(AXNames.Attribute.focused, of: element)
        let selected = client.boolAttribute(AXNames.Attribute.selected, of: element)
        let actions = client.actionNames(of: element)
        let parameterizedAttributes = client.parameterizedAttributeNames(of: element)
        let attributeNames = client.attributeNames(of: element)
        let settableAttributes = client.settableAttributes(of: element, within: attributeNames)
        let cgFrame = client.frame(of: element)
        let frame = cgFrame.map { LMNHRect($0) }
        let children = children(of: element, mode: context.options.mode)
        let isSecureTextEntry = Self.isSecureTextEntry(role: role, subrole: subrole)
        let value = redactor.preview(
            client.attributeValue(AXNames.Attribute.value, of: element),
            role: role,
            isSecureTextEntry: isSecureTextEntry
        )
        let label = Self.bestLabel(title: title, description: description, placeholder: placeholder, valuePreview: value.preview)
        let pathComponent = Self.pathComponent(role: role, label: label ?? context.appName)
        let elementPath = path + [pathComponent]
        let id = Self.elementId(
            snapshotShortId: context.shortSnapshotId,
            index: context.nodeIndex,
            role: role,
            fallback: "element"
        )
        let visible = frame?.isUsableFrame ?? true
        let risk = safetyClassifier.classifyElement(
            role: role,
            title: title,
            label: label,
            valuePreview: value.preview,
            isSecureTextEntry: isSecureTextEntry
        )
        let defaultAction = Self.defaultAction(actions: actions, settableAttributes: settableAttributes, role: role)
        let selector = Self.selector(role: role, label: label, path: elementPath)

        let record = AccessibilityElementRecord(
            id: id,
            parentId: parentId,
            processIdentifier: context.processIdentifier,
            bundleIdentifier: context.bundleIdentifier,
            role: role,
            subrole: subrole,
            roleDescription: roleDescription,
            title: title,
            label: label,
            description: description,
            help: help,
            valuePreview: value.preview,
            valueLength: value.length,
            valueTruncated: value.truncated,
            valueAvailable: value.available,
            placeholder: placeholder,
            enabled: enabled,
            focused: focused,
            selected: selected,
            frame: frame,
            visible: visible,
            actions: actions,
            settableAttributes: settableAttributes,
            parameterizedAttributes: parameterizedAttributes,
            childrenCount: children.count,
            path: elementPath,
            defaultAction: defaultAction,
            selector: selector,
            risk: risk
        )

        let shouldInclude = shouldIncludeRecord(record, depth: depth, mode: context.options.mode)
        context.nodeIndex += 1

        if shouldInclude {
            context.records.append(record)
            context.registryEntries.append(RegisteredElement(snapshotId: context.snapshotId, record: record, handle: element))
        }

        guard depth < context.options.maxDepth else {
            return
        }

        for (index, child) in children.enumerated() {
            traverse(
                child,
                parentId: shouldInclude ? id : parentId,
                depth: depth + 1,
                path: elementPath,
                siblingIndex: index,
                context: &context
            )
        }
    }

    private func children(of element: AXElementHandle, mode: SnapshotMode) -> [AXElementHandle] {
        if mode == .summary {
            let visibleChildren = client.arrayAttribute(AXNames.Attribute.visibleChildren, of: element)
            if !visibleChildren.isEmpty {
                return visibleChildren
            }
        }

        let navigationChildren = client.arrayAttribute(AXNames.Attribute.childrenInNavigationOrder, of: element)
        if !navigationChildren.isEmpty {
            return navigationChildren
        }

        let children = client.arrayAttribute(AXNames.Attribute.children, of: element)
        if !children.isEmpty {
            return children
        }

        return client.arrayAttribute(AXNames.Attribute.visibleChildren, of: element)
    }

    private func shouldIncludeRecord(_ record: AccessibilityElementRecord, depth: Int, mode: SnapshotMode) -> Bool {
        switch mode {
        case .full:
            true
        case .standard:
            depth <= 2 || isInteractive(record) || record.focused == true || record.selected == true
        case .summary:
            depth <= 1 || isInteractive(record) || record.focused == true
        }
    }

    private func isInteractive(_ record: AccessibilityElementRecord) -> Bool {
        !record.actions.isEmpty ||
            record.settableAttributes.contains(AXNames.Attribute.value) ||
            (record.enabled == true && (record.role?.contains("Button") == true || record.role?.contains("Text") == true))
    }

    private static func shortSnapshotId(_ snapshotId: String) -> String {
        String(snapshotId.replacingOccurrences(of: "-", with: "").suffix(8))
    }

    private static func elementId(snapshotShortId: String, index: Int, role: String?, fallback: String) -> String {
        let slug = (role ?? fallback)
            .replacingOccurrences(of: "AX", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return "el_\(snapshotShortId)_\(String(format: "%04d", index))_\(slug.isEmpty ? fallback : slug)"
    }

    private static func bestLabel(title: String?, description: String?, placeholder: String?, valuePreview: String?) -> String? {
        [title, description, placeholder, valuePreview]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .first
    }

    private static func pathComponent(role: String?, label: String?) -> String {
        let role = role ?? "AXElement"
        guard let label, !label.isEmpty else {
            return role
        }
        return "\(role):\(label)"
    }

    private static func selector(role: String?, label: String?, path: [String]) -> String {
        if let label, let role {
            return "\(role)[label=\"\(label)\"]"
        }
        return path.joined(separator: " > ")
    }

    private static func defaultAction(actions: [String], settableAttributes: [String], role: String?) -> String? {
        if actions.contains(AXNames.Action.press) {
            return "press"
        }
        if settableAttributes.contains(AXNames.Attribute.value) {
            return "set_value"
        }
        if actions.contains(AXNames.Action.showMenu) {
            return "show_menu"
        }
        if role?.contains("Text") == true {
            return "type"
        }
        return nil
    }

    private static func isSecureTextEntry(role: String?, subrole: String?) -> Bool {
        [role, subrole]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("secure") || $0.contains("password") }
    }

    private struct BuildContext {
        var snapshotId: String
        var shortSnapshotId: String
        var processIdentifier: Int32
        var bundleIdentifier: String?
        var appName: String?
        var options: AXTreeBuildOptions
        var nodeIndex = 0
        var records: [AccessibilityElementRecord] = []
        var registryEntries: [RegisteredElement] = []
        var warnings: [String] = []
        var visited: Set<CFHashCode> = []
    }
}
