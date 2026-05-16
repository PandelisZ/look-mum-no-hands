import Foundation

public struct AccessibilityElementRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var parentId: String?
    public var processIdentifier: Int32
    public var bundleIdentifier: String?
    public var role: String?
    public var subrole: String?
    public var roleDescription: String?
    public var title: String?
    public var label: String?
    public var description: String?
    public var help: String?
    public var valuePreview: String?
    public var valueLength: Int?
    public var valueTruncated: Bool
    public var valueAvailable: Bool
    public var placeholder: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var selected: Bool?
    public var frame: LMNHRect?
    public var visible: Bool
    public var actions: [String]
    public var settableAttributes: [String]
    public var parameterizedAttributes: [String]
    public var childrenCount: Int
    public var path: [String]
    public var defaultAction: String?
    public var selector: String
    public var risk: InteractionRisk

    public init(
        id: String,
        parentId: String?,
        processIdentifier: Int32,
        bundleIdentifier: String?,
        role: String?,
        subrole: String?,
        roleDescription: String?,
        title: String?,
        label: String?,
        description: String?,
        help: String?,
        valuePreview: String?,
        valueLength: Int?,
        valueTruncated: Bool,
        valueAvailable: Bool,
        placeholder: String?,
        enabled: Bool?,
        focused: Bool?,
        selected: Bool?,
        frame: LMNHRect?,
        visible: Bool,
        actions: [String],
        settableAttributes: [String],
        parameterizedAttributes: [String],
        childrenCount: Int,
        path: [String],
        defaultAction: String?,
        selector: String,
        risk: InteractionRisk
    ) {
        self.id = id
        self.parentId = parentId
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.roleDescription = roleDescription
        self.title = title
        self.label = label
        self.description = description
        self.help = help
        self.valuePreview = valuePreview
        self.valueLength = valueLength
        self.valueTruncated = valueTruncated
        self.valueAvailable = valueAvailable
        self.placeholder = placeholder
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.frame = frame
        self.visible = visible
        self.actions = actions
        self.settableAttributes = settableAttributes
        self.parameterizedAttributes = parameterizedAttributes
        self.childrenCount = childrenCount
        self.path = path
        self.defaultAction = defaultAction
        self.selector = selector
        self.risk = risk
    }
}
