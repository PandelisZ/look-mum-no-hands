import CoreGraphics
import Foundation

public enum VirtualCursorCoordinateConverter {
    /// LMNH stores AX/WindowServer points in global display points with a top-left Y origin.
    /// AppKit overlay views draw in their local bottom-left coordinate system.
    public static func localPoint(fromGlobalTopLeft point: CGPoint, inScreenFrame screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: point.x - screenFrame.minX,
            y: screenFrame.maxY - point.y
        )
    }

    public static func localRect(fromGlobalTopLeft rect: CGRect, inScreenFrame screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func screenFrame(_ screenFrame: CGRect, containsGlobalTopLeft point: CGPoint) -> Bool {
        point.x >= screenFrame.minX
            && point.x <= screenFrame.maxX
            && point.y >= screenFrame.minY
            && point.y <= screenFrame.maxY
    }
}
