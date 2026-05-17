import Foundation

public enum VirtualCursorTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case pinkArrow = "pink_arrow"
    case customCurser = "custom_curser"
    case flameBlack = "flame_black"
    case tardis = "tardis"
    case crosshairGreen = "crosshair_green"
    case gunAdvanced = "gun_advanced"
    case shiningSword = "shining_sword"
    case runescapeDragonDagger = "runescape_dragon_dagger"
    case sportsArchery = "sports_archery"
    case diamondTools = "diamond_tools"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pinkArrow: "Pink LMNH"
        case .customCurser: "Custom Cursor"
        case .flameBlack: "Flame 2black"
        case .tardis: "TARDIS"
        case .crosshairGreen: "Crosshair Green"
        case .gunAdvanced: "Gun Advanced"
        case .shiningSword: "Shining Sword"
        case .runescapeDragonDagger: "RuneScape DDS"
        case .sportsArchery: "Sports Archery"
        case .diamondTools: "Diamond Tools"
        }
    }

    public var usesTint: Bool {
        switch self {
        case .pinkArrow:
            true
        case .customCurser, .flameBlack, .tardis, .crosshairGreen, .gunAdvanced, .shiningSword,
             .runescapeDragonDagger, .sportsArchery, .diamondTools:
            false
        }
    }

    public var sourceAttribution: String? {
        switch self {
        case .customCurser:
            "custom curser.ani, CC BY, rw-designer.com"
        case .flameBlack:
            "flame 2black.ani, CC BY, rw-designer.com"
        case .tardis:
            "TARDIS.ani by Vlasta, CC BY, rw-designer.com"
        case .crosshairGreen:
            "Crosshair Cursors by morten8035, CC BY, rw-designer.com"
        case .gunAdvanced:
            "Gun Advanced Cursors by The Sword of the Heart, CC BY, rw-designer.com"
        case .shiningSword:
            "Swords Cursors by Mr. Zidgel, CC BY, rw-designer.com"
        case .runescapeDragonDagger:
            "Runescape DDS With Animated Special+ More Cursors by Tylo222, CC BY, rw-designer.com"
        case .sportsArchery:
            "Sports Gear Cursors by Daniel W., CC BY, rw-designer.com"
        case .diamondTools:
            "Minecraft - Diamond Tools Cursors by Ultra Ninja, public domain, rw-designer.com"
        case .pinkArrow:
            nil
        }
    }

    public var defaultAppearance: VirtualCursorAppearance {
        switch self {
        case .pinkArrow:
            VirtualCursorAppearance(theme: self, red: 1.0, green: 0.18, blue: 0.62)
        case .customCurser, .flameBlack, .tardis, .crosshairGreen, .gunAdvanced, .shiningSword,
             .runescapeDragonDagger, .sportsArchery, .diamondTools:
            VirtualCursorAppearance(theme: self, red: 0.18, green: 0.54, blue: 1.0)
        }
    }
}

public struct VirtualCursorAppearance: Codable, Equatable, Sendable {
    public static let didChangeNotification = Notification.Name("com.look-mum-no-hands.cursor-appearance.changed")

    public var theme: VirtualCursorTheme
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public var scale: Double
    public var animationDuration: Double
    public var showLabels: Bool
    public var showPath: Bool

    public init(
        theme: VirtualCursorTheme = .pinkArrow,
        red: Double = 1.0,
        green: Double = 0.18,
        blue: Double = 0.62,
        alpha: Double = 1.0,
        scale: Double = 1.0,
        animationDuration: Double = 0.42,
        showLabels: Bool = true,
        showPath: Bool = true
    ) {
        self.theme = theme
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.scale = scale
        self.animationDuration = animationDuration
        self.showLabels = showLabels
        self.showPath = showPath
    }

    public static let defaultPink = VirtualCursorAppearance()

    public static func load() -> VirtualCursorAppearance {
        LMNHPaths.ensureStateDirectories()

        if let appearance = decode(from: LMNHPaths.cursorAppearanceFile) {
            return appearance.normalized
        }

        if let legacyAppearance = decode(from: LMNHPaths.legacyCursorAppearanceFile) {
            try? legacyAppearance.normalized.save()
            return legacyAppearance.normalized
        }

        let defaultAppearance = VirtualCursorAppearance.defaultPink
        if !FileManager.default.fileExists(atPath: LMNHPaths.cursorAppearanceFile.path) {
            try? defaultAppearance.save()
        }
        return defaultAppearance
    }

    public func save() throws {
        LMNHPaths.ensureStateDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: LMNHPaths.cursorAppearanceFile, options: .atomic)
        DistributedNotificationCenter.default().postNotificationName(
            Self.didChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public var normalized: VirtualCursorAppearance {
        VirtualCursorAppearance(
            theme: theme,
            red: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            alpha: alpha.clamped(to: 0.1...1),
            scale: scale.clamped(to: 0.5...2.5),
            animationDuration: animationDuration.clamped(to: 0.05...2.0),
            showLabels: showLabels,
            showPath: showPath
        )
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case red
        case green
        case blue
        case alpha
        case scale
        case animationDuration
        case showLabels
        case showPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            theme: try container.decodeIfPresent(VirtualCursorTheme.self, forKey: .theme) ?? .pinkArrow,
            red: try container.decodeIfPresent(Double.self, forKey: .red) ?? 1.0,
            green: try container.decodeIfPresent(Double.self, forKey: .green) ?? 0.18,
            blue: try container.decodeIfPresent(Double.self, forKey: .blue) ?? 0.62,
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0,
            scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0,
            animationDuration: try container.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.42,
            showLabels: try container.decodeIfPresent(Bool.self, forKey: .showLabels) ?? true,
            showPath: try container.decodeIfPresent(Bool.self, forKey: .showPath) ?? true
        )
    }

    private static func decode(from url: URL) -> VirtualCursorAppearance? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(VirtualCursorAppearance.self, from: data)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
