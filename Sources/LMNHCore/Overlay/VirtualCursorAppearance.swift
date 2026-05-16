import Foundation

public enum VirtualCursorTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case pinkArrow = "pink_arrow"
    case classicMac = "classic_mac"
    case windows2000 = "windows_2000"
    case aquaBubble = "aqua_bubble"
    case limePixel = "lime_pixel"
    case goldenGlove = "golden_glove"
    case rocket = "rocket"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pinkArrow: "Pink LMNH"
        case .classicMac: "Classic Mac"
        case .windows2000: "Windows 2000"
        case .aquaBubble: "Aqua Bubble"
        case .limePixel: "Lime Pixel"
        case .goldenGlove: "Golden Glove"
        case .rocket: "Rocket"
        }
    }

    public var defaultAppearance: VirtualCursorAppearance {
        switch self {
        case .pinkArrow:
            VirtualCursorAppearance(theme: self, red: 1.0, green: 0.18, blue: 0.62)
        case .classicMac:
            VirtualCursorAppearance(theme: self, red: 0.08, green: 0.08, blue: 0.08)
        case .windows2000:
            VirtualCursorAppearance(theme: self, red: 0.05, green: 0.22, blue: 0.85)
        case .aquaBubble:
            VirtualCursorAppearance(theme: self, red: 0.12, green: 0.78, blue: 1.0)
        case .limePixel:
            VirtualCursorAppearance(theme: self, red: 0.52, green: 1.0, blue: 0.08)
        case .goldenGlove:
            VirtualCursorAppearance(theme: self, red: 1.0, green: 0.72, blue: 0.16)
        case .rocket:
            VirtualCursorAppearance(theme: self, red: 1.0, green: 0.25, blue: 0.18)
        }
    }
}

public struct VirtualCursorAppearance: Codable, Equatable, Sendable {
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
        guard let data = try? Data(contentsOf: LMNHPaths.cursorAppearanceFile),
              let appearance = try? JSONDecoder().decode(VirtualCursorAppearance.self, from: data) else {
            return .defaultPink
        }
        return appearance.normalized
    }

    public func save() throws {
        LMNHPaths.ensureStateDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: LMNHPaths.cursorAppearanceFile, options: .atomic)
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
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
