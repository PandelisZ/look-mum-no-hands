import CoreGraphics
import Foundation

public struct LMNHPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var coordinateSpace: String

    public init(x: Double, y: Double, coordinateSpace: String = "global_display_points") {
        self.x = x
        self.y = y
        self.coordinateSpace = coordinateSpace
    }

    public init(_ point: CGPoint, coordinateSpace: String = "global_display_points") {
        self.init(x: point.x, y: point.y, coordinateSpace: coordinateSpace)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct LMNHSize: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

public struct LMNHRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var coordinateSpace: String

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        coordinateSpace: String = "global_display_points"
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.coordinateSpace = coordinateSpace
    }

    public init(_ rect: CGRect, coordinateSpace: String = "global_display_points") {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height,
            coordinateSpace: coordinateSpace
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var center: LMNHPoint {
        LMNHPoint(x: x + width / 2, y: y + height / 2, coordinateSpace: coordinateSpace)
    }

    public var isUsableFrame: Bool {
        width > 0 && height > 0 && x.isFinite && y.isFinite && width.isFinite && height.isFinite
    }
}
