import LMNHCore
import SwiftUI

struct CursorPreview: View {
    let appearance: VirtualCursorAppearance

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let progress = (sin(t * 2.2) + 1) / 2
                let eased = 1 - pow(1 - progress, 3)
                let start = CGPoint(x: 54, y: size.height - 34)
                let end = CGPoint(x: size.width - 70, y: 34)
                let point = CGPoint(
                    x: start.x + (end.x - start.x) * eased,
                    y: start.y + (end.y - start.y) * eased
                )
                let color = Color(
                    red: appearance.normalized.red,
                    green: appearance.normalized.green,
                    blue: appearance.normalized.blue,
                    opacity: appearance.normalized.alpha
                )

                var path = Path()
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x, y: end.y),
                    control2: CGPoint(x: end.x, y: start.y)
                )
                context.stroke(path, with: .color(color.opacity(0.28)), style: StrokeStyle(lineWidth: 3, dash: [6, 7]))
                context.stroke(Path(ellipseIn: CGRect(center: end, radius: 12)), with: .color(color.opacity(0.7)), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(center: start, radius: 5)), with: .color(color.opacity(0.4)))
                if let frame = VirtualCursorArtwork.bitmapFrame(for: appearance.normalized.theme, at: timeline.date) {
                    let scale = CGFloat(appearance.normalized.scale * 1.6)
                    let size = CGSize(width: frame.baseSize.width * scale, height: frame.baseSize.height * scale)
                    let origin = CGPoint(
                        x: point.x - frame.hotspot.x * scale,
                        y: point.y - frame.hotspot.y * scale
                    )
                    context.draw(Image(nsImage: frame.image), in: CGRect(origin: origin, size: size))
                    return
                }
                let cursor = cursorPath(at: point, scale: appearance.normalized.scale)
                if appearance.normalized.theme == .pinkArrow {
                    var shadowContext = context
                    shadowContext.translateBy(x: 3, y: 3)
                    shadowContext.fill(cursor, with: .color(.black.opacity(0.22)))
                    context.stroke(cursor, with: .color(.white.opacity(0.96)), lineWidth: 5)
                    context.fill(cursor, with: .color(.black.opacity(0.86)))
                    context.stroke(cursor, with: .color(.white.opacity(0.55)), lineWidth: 1.3)
                } else {
                    context.fill(cursor, with: .color(color))
                    context.stroke(cursor, with: .color(.white.opacity(0.92)), lineWidth: 1.5)
                }
            }
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.84), .purple.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func cursorPath(at point: CGPoint, scale: Double) -> Path {
        arrowPath(at: point, scale: CGFloat(scale))
    }

    private func arrowPath(at point: CGPoint, scale s: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x + 10 * s, y: point.y + 34 * s))
        path.addLine(to: CGPoint(x: point.x + 28 * s, y: point.y + 18 * s))
        path.closeSubpath()
        return path
    }

}

struct CursorThemeThumbnail: View {
    let appearance: VirtualCursorAppearance

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let normalized = appearance.normalized
                let color = Color(
                    red: normalized.red,
                    green: normalized.green,
                    blue: normalized.blue,
                    opacity: normalized.alpha
                )
                let point = CGPoint(x: size.width * 0.24, y: size.height * 0.18)

                if let frame = VirtualCursorArtwork.bitmapFrame(for: normalized.theme, at: timeline.date) {
                    let fit = min(size.width / frame.baseSize.width, size.height / frame.baseSize.height) * 0.84
                    let drawSize = CGSize(width: frame.baseSize.width * fit, height: frame.baseSize.height * fit)
                    let origin = CGPoint(
                        x: (size.width - drawSize.width) / 2,
                        y: (size.height - drawSize.height) / 2
                    )
                    context.draw(Image(nsImage: frame.image), in: CGRect(origin: origin, size: drawSize))
                    return
                }

                let cursor = arrowPath(at: point, scale: 0.92)
                if normalized.theme == .pinkArrow {
                    var shadowContext = context
                    shadowContext.translateBy(x: 2, y: 2)
                    shadowContext.fill(cursor, with: .color(.black.opacity(0.24)))
                    context.stroke(cursor, with: .color(.white.opacity(0.96)), lineWidth: 4)
                    context.fill(cursor, with: .color(.black.opacity(0.86)))
                    context.stroke(cursor, with: .color(.white.opacity(0.55)), lineWidth: 1)
                } else {
                    context.fill(cursor, with: .color(color))
                    context.stroke(cursor, with: .color(.white.opacity(0.92)), lineWidth: 1.5)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.22))
        )
    }

    private func arrowPath(at point: CGPoint, scale s: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x + 10 * s, y: point.y + 34 * s))
        path.addLine(to: CGPoint(x: point.x + 28 * s, y: point.y + 18 * s))
        path.closeSubpath()
        return path
    }

}

private extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
