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
            subdirectory: "Cursors/RealWorldPointers"
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
    var imageName: String
    var hotspot: CGPoint
    var baseSize: CGSize
    var frameCount: Int
    var frameDuration: TimeInterval

    init(
        imageName: String,
        hotspot: CGPoint,
        baseSize: CGSize,
        frameCount: Int = 1,
        frameDuration: TimeInterval = 0
    ) {
        self.imageName = imageName
        self.hotspot = hotspot
        self.baseSize = baseSize
        self.frameCount = frameCount
        self.frameDuration = frameDuration
    }

    init?(theme: VirtualCursorTheme) {
        switch theme {
        case .customCurser:
            self.init(
                imageName: "custom-curser",
                hotspot: CGPoint(x: 9, y: 2),
                baseSize: CGSize(width: 32, height: 32),
                frameCount: 12,
                frameDuration: 0.8
            )
        case .flameBlack:
            self.init(
                imageName: "flame-2black",
                hotspot: CGPoint(x: 0, y: 0),
                baseSize: CGSize(width: 32, height: 32),
                frameCount: 7,
                frameDuration: 1.1666666666667
            )
        case .tardis:
            self.init(
                imageName: "tardis",
                hotspot: CGPoint(x: 15, y: 15),
                baseSize: CGSize(width: 32, height: 32),
                frameCount: 40,
                frameDuration: 3.3333333333333
            )
        case .crosshairGreen:
            self.init(
                imageName: "crosshair-green",
                hotspot: CGPoint(x: 16, y: 16),
                baseSize: CGSize(width: 32, height: 32)
            )
        case .gunAdvanced:
            self.init(
                imageName: "gun-advanced",
                hotspot: CGPoint(x: 9, y: 9),
                baseSize: CGSize(width: 32, height: 32)
            )
        case .shiningSword:
            self.init(
                imageName: "shining-sword",
                hotspot: CGPoint(x: 15, y: 2),
                baseSize: CGSize(width: 32, height: 32),
                frameCount: 8,
                frameDuration: 1.5333333333333
            )
        case .pinkArrow:
            return nil
        }
    }

    func frameName(at date: Date) -> String {
        guard frameCount > 1, frameDuration > 0 else {
            return imageName
        }

        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: frameDuration)
        let frameIndex = min(Int((progress / frameDuration) * Double(frameCount)), frameCount - 1)
        return "\(imageName)-\(String(format: "%02d", frameIndex))"
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
        rotation: CGFloat = 0,
        date: Date = Date()
    ) {
        let draw = {
            drawCursorWithoutTransform(
                theme: theme,
                at: point,
                scale: scale,
                tint: color,
                alpha: alpha,
                date: date
            )
        }

        guard abs(rotation) > 0.001 else {
            draw()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.rotate(byRadians: rotation)
        transform.translateX(by: -point.x, yBy: -point.y)
        transform.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawCursorWithoutTransform(
        theme: VirtualCursorTheme,
        at point: CGPoint,
        scale: CGFloat,
        tint color: NSColor,
        alpha: CGFloat,
        date: Date
    ) {
        if let frame = VirtualCursorArtwork.bitmapFrame(for: theme, at: date) {
            drawBitmapFrame(frame, at: point, scale: scale, alpha: alpha)
            return
        }

        let path = arrowPath(at: point, scale: scale)
        NSColor.black.withAlphaComponent(0.22).setFill()
        let shadow = arrowPath(at: point.offsetBy(dx: 3 * scale, dy: -3 * scale), scale: scale)
        shadow.fill()
        NSColor.white.withAlphaComponent(0.96).setStroke()
        path.lineWidth = 5 * scale
        path.stroke()
        NSColor(calibratedWhite: 0.12, alpha: alpha).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1.3 * scale
        path.stroke()
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
            y: point.y - size.height + frame.hotspot.y * scale
        )
        frame.image.draw(
            in: CGRect(origin: origin, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: alpha
        )
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
