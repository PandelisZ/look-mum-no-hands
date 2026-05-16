import AppKit

public struct VirtualCursorBitmapFrame {
    public var image: NSImage
    public var hotspot: CGPoint
    public var baseSize: CGSize

    public init(image: NSImage, hotspot: CGPoint, baseSize: CGSize) {
        self.image = image
        self.hotspot = hotspot
        self.baseSize = baseSize
    }
}

@MainActor
public enum VirtualCursorArtwork {
    private static var imageCache: [String: NSImage] = [:]

    public static func bitmapFrame(for theme: VirtualCursorTheme, at date: Date = Date()) -> VirtualCursorBitmapFrame? {
        guard let metadata = BitmapCursorMetadata(theme: theme) else {
            return nil
        }

        let frameName = metadata.frameName(at: date)
        guard let image = cachedImage(named: frameName) else {
            return nil
        }

        return VirtualCursorBitmapFrame(
            image: image,
            hotspot: metadata.hotspot,
            baseSize: metadata.baseSize
        )
    }

    public static func attribution(for theme: VirtualCursorTheme) -> String? {
        theme.sourceAttribution
    }

    private static func cachedImage(named name: String) -> NSImage? {
        if let image = imageCache[name] {
            return image
        }

        let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Cursors/RealWorldBlueSilver"
        ) ?? Bundle.module.url(
            forResource: name,
            withExtension: "png"
        )
        guard let url, let image = NSImage(contentsOf: url) else {
            return nil
        }

        imageCache[name] = image
        return image
    }
}

private struct BitmapCursorMetadata {
    var framePrefix: String
    var frameCount: Int
    var hotspot: CGPoint
    var baseSize: CGSize
    var duration: TimeInterval

    init(
        framePrefix: String,
        frameCount: Int,
        hotspot: CGPoint,
        baseSize: CGSize,
        duration: TimeInterval
    ) {
        self.framePrefix = framePrefix
        self.frameCount = frameCount
        self.hotspot = hotspot
        self.baseSize = baseSize
        self.duration = duration
    }

    init?(theme: VirtualCursorTheme) {
        switch theme {
        case .realWorldBlueSilver:
            self.init(
                framePrefix: "rw-arrow",
                frameCount: 1,
                hotspot: CGPoint(x: 2, y: 3),
                baseSize: CGSize(width: 63, height: 63),
                duration: 2.4
            )
        case .realWorldAppStarting:
            self.init(
                framePrefix: "rw-app-starting",
                frameCount: 18,
                hotspot: CGPoint(x: 2, y: 3),
                baseSize: CGSize(width: 32, height: 32),
                duration: 2.4
            )
        case .realWorldBusy:
            self.init(
                framePrefix: "rw-busy",
                frameCount: 36,
                hotspot: CGPoint(x: 15, y: 15),
                baseSize: CGSize(width: 32, height: 32),
                duration: 2.4
            )
        case .pinkArrow, .classicMac, .windows2000, .aquaBubble, .limePixel, .goldenGlove, .rocket:
            return nil
        }
    }

    func frameName(at date: Date) -> String {
        guard frameCount > 1 else {
            return framePrefix
        }

        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        let frameIndex = min(Int(progress * Double(frameCount)), frameCount - 1)
        return "\(framePrefix)-\(String(format: "%02d", frameIndex))"
    }
}

@MainActor
enum VirtualCursorThemePainter {
    static func drawCursor(
        theme: VirtualCursorTheme,
        at point: CGPoint,
        scale: CGFloat,
        tint color: NSColor,
        alpha: CGFloat,
        date: Date = Date()
    ) {
        if let frame = VirtualCursorArtwork.bitmapFrame(for: theme, at: date) {
            drawBitmapFrame(frame, at: point, scale: scale, alpha: alpha)
            return
        }

        let path = cursorPath(for: theme, at: point, scale: scale)
        switch theme {
        case .classicMac:
            NSColor.white.setFill()
            path.fill()
            NSColor.black.setStroke()
            path.lineWidth = 2 * scale
            path.stroke()
        case .windows2000:
            NSColor.white.setFill()
            path.fill()
            NSColor.black.setStroke()
            path.lineWidth = 1.4 * scale
            path.stroke()
            color.withAlphaComponent(0.85).setStroke()
            let shadow = cursorPath(for: theme, at: point.offsetBy(dx: 2 * scale, dy: -2 * scale), scale: scale)
            shadow.lineWidth = 1 * scale
            shadow.stroke()
        case .aquaBubble:
            color.withAlphaComponent(0.28).setFill()
            NSBezierPath(ovalIn: CGRect(center: point.offsetBy(dx: 13 * scale, dy: -13 * scale), radius: 18 * scale)).fill()
            NSColor.white.withAlphaComponent(0.88).setStroke()
            path.lineWidth = 4 * scale
            path.stroke()
            color.withAlphaComponent(0.94).setFill()
            path.fill()
        case .limePixel:
            NSColor.black.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3 * scale
            path.stroke()
            color.withAlphaComponent(0.98).setFill()
            path.fill()
        case .goldenGlove:
            NSColor.black.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 3 * scale
            path.stroke()
            color.withAlphaComponent(0.96).setFill()
            path.fill()
        case .rocket:
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3 * scale
            path.stroke()
            color.withAlphaComponent(0.95).setFill()
            path.fill()
            NSColor.systemOrange.withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: CGRect(center: point.offsetBy(dx: 17 * scale, dy: -27 * scale), radius: 5 * scale)).fill()
        case .pinkArrow:
            NSColor.black.withAlphaComponent(0.22).setFill()
            let shadow = cursorPath(for: theme, at: point.offsetBy(dx: 3 * scale, dy: -3 * scale), scale: scale)
            shadow.fill()
            NSColor.white.withAlphaComponent(0.96).setStroke()
            path.lineWidth = 5 * scale
            path.stroke()
            NSColor(calibratedWhite: 0.12, alpha: alpha).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 1.3 * scale
            path.stroke()
        case .realWorldBlueSilver, .realWorldAppStarting, .realWorldBusy:
            break
        }
    }

    private static func drawBitmapFrame(
        _ frame: VirtualCursorBitmapFrame,
        at point: CGPoint,
        scale: CGFloat,
        alpha: CGFloat
    ) {
        let size = CGSize(width: frame.baseSize.width * scale, height: frame.baseSize.height * scale)
        let origin = CGPoint(
            x: point.x - frame.hotspot.x * scale,
            y: point.y - frame.hotspot.y * scale
        )
        frame.image.draw(
            in: CGRect(origin: origin, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: alpha
        )
    }

    private static func cursorPath(for theme: VirtualCursorTheme, at point: CGPoint, scale: CGFloat) -> NSBezierPath {
        switch theme {
        case .classicMac, .pinkArrow, .windows2000:
            arrowPath(at: point, scale: scale)
        case .aquaBubble:
            roundedArrowPath(at: point, scale: scale)
        case .limePixel:
            pixelCursorPath(at: point, scale: scale)
        case .goldenGlove:
            gloveCursorPath(at: point, scale: scale)
        case .rocket:
            rocketCursorPath(at: point, scale: scale)
        case .realWorldBlueSilver, .realWorldAppStarting, .realWorldBusy:
            NSBezierPath()
        }
    }

    private static func arrowPath(at point: CGPoint, scale: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point)
        path.line(to: CGPoint(x: point.x + 10 * scale, y: point.y - 34 * scale))
        path.line(to: CGPoint(x: point.x + 28 * scale, y: point.y - 18 * scale))
        path.close()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        return path
    }

    private static func roundedArrowPath(at point: CGPoint, scale: CGFloat) -> NSBezierPath {
        let path = arrowPath(at: point, scale: scale)
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        return path
    }

    private static func pixelCursorPath(at point: CGPoint, scale: CGFloat) -> NSBezierPath {
        let unit = 5 * scale
        let path = NSBezierPath()
        path.move(to: point)
        path.line(to: CGPoint(x: point.x, y: point.y - 7 * unit))
        path.line(to: CGPoint(x: point.x + unit, y: point.y - 7 * unit))
        path.line(to: CGPoint(x: point.x + unit, y: point.y - 5 * unit))
        path.line(to: CGPoint(x: point.x + 2 * unit, y: point.y - 5 * unit))
        path.line(to: CGPoint(x: point.x + 2 * unit, y: point.y - 6 * unit))
        path.line(to: CGPoint(x: point.x + 3 * unit, y: point.y - 6 * unit))
        path.line(to: CGPoint(x: point.x + 3 * unit, y: point.y - 4 * unit))
        path.line(to: CGPoint(x: point.x + 5 * unit, y: point.y - 4 * unit))
        path.close()
        return path
    }

    private static func gloveCursorPath(at point: CGPoint, scale: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point)
        path.curve(to: CGPoint(x: point.x + 8 * scale, y: point.y - 28 * scale), controlPoint1: CGPoint(x: point.x + 2 * scale, y: point.y - 9 * scale), controlPoint2: CGPoint(x: point.x + 4 * scale, y: point.y - 19 * scale))
        path.curve(to: CGPoint(x: point.x + 18 * scale, y: point.y - 21 * scale), controlPoint1: CGPoint(x: point.x + 12 * scale, y: point.y - 30 * scale), controlPoint2: CGPoint(x: point.x + 18 * scale, y: point.y - 28 * scale))
        path.curve(to: CGPoint(x: point.x + 30 * scale, y: point.y - 10 * scale), controlPoint1: CGPoint(x: point.x + 24 * scale, y: point.y - 21 * scale), controlPoint2: CGPoint(x: point.x + 30 * scale, y: point.y - 17 * scale))
        path.curve(to: CGPoint(x: point.x + 14 * scale, y: point.y - 2 * scale), controlPoint1: CGPoint(x: point.x + 29 * scale, y: point.y - 1 * scale), controlPoint2: CGPoint(x: point.x + 20 * scale, y: point.y + 2 * scale))
        path.close()
        return path
    }

    private static func rocketCursorPath(at point: CGPoint, scale: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point)
        path.line(to: CGPoint(x: point.x + 13 * scale, y: point.y - 38 * scale))
        path.line(to: CGPoint(x: point.x + 22 * scale, y: point.y - 22 * scale))
        path.line(to: CGPoint(x: point.x + 34 * scale, y: point.y - 18 * scale))
        path.line(to: CGPoint(x: point.x + 22 * scale, y: point.y - 12 * scale))
        path.line(to: CGPoint(x: point.x + 17 * scale, y: point.y - 2 * scale))
        path.close()
        return path
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}

private extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}
