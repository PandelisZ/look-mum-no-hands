import CoreGraphics
import Foundation

struct VirtualCursorMotion {
    private static let maxRotation = Double.pi * 0.14
    private static let uprightHeading = Double.pi * 0.75
    private static let minimumTravelDistance: CGFloat = 2
    static let clickPulseDuration: TimeInterval = 0.24

    static func rotation(
        start: CGPoint?,
        end: CGPoint?,
        at date: Date,
        startedAt: Date,
        duration: TimeInterval
    ) -> CGFloat {
        guard let start,
              let end,
              duration > 0,
              start.distance(to: end) > minimumTravelDistance else {
            return 0
        }

        let progress = min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
        guard progress < 1 else {
            return 0
        }

        let heading = atan2(Double(end.y - start.y), Double(end.x - start.x))
        let travelRotation = wrappedAngle(heading - uprightHeading)
        let limitedRotation = min(max(travelRotation, -maxRotation), maxRotation)
        let returnEnvelope = sin(Double.pi * easeOutCubic(progress))
        return CGFloat(limitedRotation * returnEnvelope)
    }

    static func clickScale(startedAt: Date?, at date: Date) -> CGFloat {
        guard let startedAt else {
            return 1
        }

        let progress = min(max(date.timeIntervalSince(startedAt) / clickPulseDuration, 0), 1)
        guard progress < 1 else {
            return 1
        }

        let compression: Double
        if progress < 0.35 {
            compression = easeOutCubic(progress / 0.35)
        } else {
            compression = 1 - easeOutCubic((progress - 0.35) / 0.65)
        }

        return CGFloat(1 - 0.1 * compression)
    }

    private static func wrappedAngle(_ angle: Double) -> Double {
        var value = angle
        while value <= -Double.pi {
            value += Double.pi * 2
        }
        while value > Double.pi {
            value -= Double.pi * 2
        }
        return value
    }

    private static func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
