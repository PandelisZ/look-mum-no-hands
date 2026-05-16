import ApplicationServices
import CoreGraphics
import Foundation

public struct AXValueBridge: Sendable {
    public init() {}

    public func point(from value: Any?) -> CGPoint? {
        guard let axValue = axValue(from: value), AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    public func size(from value: Any?) -> CGSize? {
        guard let axValue = axValue(from: value), AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    public func rect(from value: Any?) -> CGRect? {
        guard let axValue = axValue(from: value), AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }
        return rect
    }

    public func rangeDescription(from value: Any?) -> String? {
        guard let axValue = axValue(from: value), AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return "\(range.location):\(range.length)"
    }

    private func axValue(from value: Any?) -> AXValue? {
        guard let value else {
            return nil
        }

        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else {
            return nil
        }

        return (value as! AXValue)
    }
}
