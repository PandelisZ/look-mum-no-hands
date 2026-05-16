import AppKit

@MainActor
public final class AppKitVirtualCursorRenderer: VirtualCursorRendering {
    private var windows: [ObjectIdentifier: VirtualCursorOverlayPanel]
    private var views: [ObjectIdentifier: VirtualCursorCanvasView]

    public static func makeIfAvailable() -> AppKitVirtualCursorRenderer? {
        guard ProcessInfo.processInfo.environment["LMNH_OVERLAY_RENDERER"] != "headless" else {
            return nil
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        return AppKitVirtualCursorRenderer(screens: screens)
    }

    public init(screens: [NSScreen] = NSScreen.screens) {
        self.windows = [:]
        self.views = [:]
        reconcileWindows(with: screens)
    }

    public func render(cursors: [VirtualCursorRecord]) {
        reconcileWindows(with: NSScreen.screens)

        for screen in NSScreen.screens {
            let id = ObjectIdentifier(screen)
            views[id]?.cursors = cursors.filter { cursor in
                guard let point = cursor.target.displayPoint else {
                    return cursor.target.path?.points.contains {
                        VirtualCursorCoordinateConverter.screenFrame(screen.frame, containsGlobalTopLeft: $0.cgPoint)
                    } ?? false
                }

                return VirtualCursorCoordinateConverter.screenFrame(screen.frame, containsGlobalTopLeft: point.cgPoint)
            }
        }
    }

    public func close() {
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }

        windows.removeAll()
        views.removeAll()
    }

    private func reconcileWindows(with screens: [NSScreen]) {
        let liveIDs = Set(screens.map(ObjectIdentifier.init))

        for id in windows.keys.filter({ !liveIDs.contains($0) }) {
            guard let window = windows[id] else {
                continue
            }

            window.orderOut(nil)
            window.close()
            windows[id] = nil
            views[id] = nil
        }

        for screen in screens {
            let id = ObjectIdentifier(screen)

            if let window = windows[id] {
                window.setFrame(screen.frame, display: true)
                continue
            }

            let view = VirtualCursorCanvasView(screen: screen)
            let window = VirtualCursorOverlayPanel(screen: screen, contentView: view)
            windows[id] = window
            views[id] = view
            window.orderFrontRegardless()
        }
    }
}

@MainActor
private final class VirtualCursorOverlayPanel: NSPanel {
    init(screen: NSScreen, contentView: NSView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        sharingType = .none
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }
}

@MainActor
private final class VirtualCursorCanvasView: NSView {
    private let screen: NSScreen
    private var animatedCursors: [String: AnimatedVirtualCursor] = [:]
    private var displayTimer: Timer?
    private var cursorAppearance = VirtualCursorAppearance.load()

    var cursors: [VirtualCursorRecord] = [] {
        didSet {
            updateAnimatedCursors()
            startDisplayTimerIfNeeded()
            needsDisplay = true
        }
    }

    init(screen: NSScreen) {
        self.screen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(false)
    }

    deinit {
        MainActor.assumeIsolated {
            displayTimer?.invalidate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        cursorAppearance = VirtualCursorAppearance.load()
        for animatedCursor in animatedCursors.values where animatedCursor.cursor.visible {
            draw(animatedCursor)
        }
    }

    private func updateAnimatedCursors() {
        let incoming = Dictionary(uniqueKeysWithValues: cursors.map { ($0.cursorID, $0) })
        animatedCursors = animatedCursors.filter { incoming[$0.key] != nil }

        for cursor in cursors {
            let endPoint = cursor.target.displayPoint?.cgPoint
            let previous = animatedCursors[cursor.cursorID]
            let currentPoint = previous?.presentationPoint(at: Date()) ?? previous?.endPoint ?? endPoint
            animatedCursors[cursor.cursorID] = AnimatedVirtualCursor(
                cursor: cursor,
                startPoint: currentPoint,
                endPoint: endPoint,
                startedAt: Date(),
                duration: cursorAppearance.normalized.animationDuration
            )
        }
    }

    private func startDisplayTimerIfNeeded() {
        guard displayTimer == nil else {
            return
        }

        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickAnimation()
            }
        }
        RunLoop.main.add(displayTimer!, forMode: .common)
    }

    private func tickAnimation() {
        guard !animatedCursors.isEmpty else {
            displayTimer?.invalidate()
            displayTimer = nil
            return
        }

        needsDisplay = true
    }

    private func draw(_ animatedCursor: AnimatedVirtualCursor) {
        let cursor = animatedCursor.cursor
        let color = NSColor(cursorAppearance.normalized)
        if let frame = cursor.target.frame {
            drawFrame(frame, color: color, state: cursor.state)
        }

        if cursor.state == .dragging, let path = cursor.target.path {
            drawDragPath(path, color: color)
        }

        guard let point = animatedCursor.presentationPoint(at: Date()) else {
            return
        }

        let localPoint = localPoint(forScreenPoint: point)
        drawJourney(for: animatedCursor, color: color)

        switch cursor.state {
        case .observing:
            drawObserving(at: localPoint, color: color)
        case .aiming:
            drawAiming(at: localPoint, color: color)
        case .pressing:
            drawPressing(at: localPoint, color: color)
        case .typing:
            drawTyping(at: localPoint, color: color)
        case .scrolling:
            drawScrolling(at: localPoint, color: color)
        case .dragging:
            drawDraggingEndpoint(at: localPoint, color: color)
        case .blocked:
            drawBlocked(at: localPoint)
        case .handoff:
            drawHandoff(at: localPoint)
        }

        if cursorAppearance.normalized.showLabels {
            drawLabel(for: cursor, at: localPoint, color: color)
        }
    }

    private func drawJourney(for animatedCursor: AnimatedVirtualCursor, color: NSColor) {
        guard cursorAppearance.normalized.showPath,
              let start = animatedCursor.startPoint,
              let end = animatedCursor.endPoint,
              start.distance(to: end) > 2 else {
            return
        }

        let localStart = localPoint(forScreenPoint: start)
        let localEnd = localPoint(forScreenPoint: end)

        color.withAlphaComponent(0.18).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2 * appearanceScale
        path.lineCapStyle = .round
        path.setLineDash([5, 7], count: 2, phase: 0)
        path.move(to: localStart)
        path.curve(
            to: localEnd,
            controlPoint1: CGPoint(x: localStart.x, y: (localStart.y + localEnd.y) / 2),
            controlPoint2: CGPoint(x: localEnd.x, y: (localStart.y + localEnd.y) / 2)
        )
        path.stroke()

        color.withAlphaComponent(0.35).setStroke()
        NSBezierPath(ovalIn: CGRect(center: localStart, radius: 5 * appearanceScale)).stroke()

        color.withAlphaComponent(0.7).setStroke()
        let destination = NSBezierPath(ovalIn: CGRect(center: localEnd, radius: 10 * appearanceScale))
        destination.lineWidth = 2 * appearanceScale
        destination.stroke()
    }

    private func drawFrame(
        _ frame: VirtualCursorFrame,
        color: NSColor,
        state: VirtualCursorState
    ) {
        let rect = localRect(forScreenRect: CGRect(
            x: CGFloat(frame.x),
            y: CGFloat(frame.y),
            width: CGFloat(frame.width),
            height: CGFloat(frame.height)
        )).insetBy(dx: -4 * appearanceScale, dy: -4 * appearanceScale)

        color.withAlphaComponent(state == .observing ? 0.4 : 0.65).setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 8 * appearanceScale, yRadius: 8 * appearanceScale)
        path.lineWidth = state == .blocked ? 3 : 2
        path.setLineDash([6, 5], count: 2, phase: 0)
        path.stroke()
    }

    private func drawObserving(at point: CGPoint, color: NSColor) {
        color.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: CGRect(center: point, radius: 22)).fill()
        color.withAlphaComponent(0.8).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(center: point, radius: 14))
        ring.lineWidth = 2
        ring.stroke()
    }

    private func drawAiming(at point: CGPoint, color: NSColor) {
        drawCursorArrow(at: point, color: color)
        color.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: CGPoint(x: point.x - 18, y: point.y))
        path.line(to: CGPoint(x: point.x - 6, y: point.y))
        path.move(to: CGPoint(x: point.x + 6, y: point.y))
        path.line(to: CGPoint(x: point.x + 18, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 18))
        path.line(to: CGPoint(x: point.x, y: point.y - 6))
        path.move(to: CGPoint(x: point.x, y: point.y + 6))
        path.line(to: CGPoint(x: point.x, y: point.y + 18))
        path.stroke()
        NSBezierPath(ovalIn: CGRect(center: point, radius: 4)).fill(with: color)
    }

    private func drawPressing(at point: CGPoint, color: NSColor) {
        drawCursorArrow(at: point, color: color)
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: CGRect(center: point, radius: 24)).fill()
        color.withAlphaComponent(0.95).setStroke()
        let ripple = NSBezierPath(ovalIn: CGRect(center: point, radius: 17))
        ripple.lineWidth = 3
        ripple.stroke()
        NSBezierPath(ovalIn: CGRect(center: point, radius: 5)).fill(with: color)
    }

    private func drawTyping(at point: CGPoint, color: NSColor) {
        drawCursorArrow(at: point.offsetBy(dx: -10, dy: 0), color: color)
        color.withAlphaComponent(0.95).setStroke()
        let caret = NSBezierPath()
        caret.lineWidth = 3
        caret.move(to: CGPoint(x: point.x, y: point.y - 16))
        caret.line(to: CGPoint(x: point.x, y: point.y + 16))
        caret.move(to: CGPoint(x: point.x - 5, y: point.y + 16))
        caret.line(to: CGPoint(x: point.x + 5, y: point.y + 16))
        caret.move(to: CGPoint(x: point.x - 5, y: point.y - 16))
        caret.line(to: CGPoint(x: point.x + 5, y: point.y - 16))
        caret.stroke()
    }

    private func drawScrolling(at point: CGPoint, color: NSColor) {
        color.withAlphaComponent(0.75).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 3
        path.move(to: CGPoint(x: point.x, y: point.y - 28))
        path.line(to: CGPoint(x: point.x, y: point.y + 28))
        path.move(to: CGPoint(x: point.x - 8, y: point.y + 18))
        path.line(to: CGPoint(x: point.x, y: point.y + 28))
        path.line(to: CGPoint(x: point.x + 8, y: point.y + 18))
        path.move(to: CGPoint(x: point.x - 8, y: point.y - 18))
        path.line(to: CGPoint(x: point.x, y: point.y - 28))
        path.line(to: CGPoint(x: point.x + 8, y: point.y - 18))
        path.stroke()
    }

    private func drawDragPath(_ cursorPath: VirtualCursorPath, color: NSColor) {
        guard let first = cursorPath.points.first else {
            return
        }

        let path = NSBezierPath()
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: localPoint(forScreenPoint: first.cgPoint))

        for point in cursorPath.points.dropFirst() {
            path.line(to: localPoint(forScreenPoint: point.cgPoint))
        }

        color.withAlphaComponent(0.72).setStroke()
        path.stroke()
    }

    private func drawDraggingEndpoint(at point: CGPoint, color: NSColor) {
        drawCursorArrow(at: point, color: color)
        color.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: CGRect(center: point, radius: 7)).fill()
    }

    private func drawCursorArrow(at point: CGPoint, color: NSColor) {
        let appearance = cursorAppearance.normalized
        VirtualCursorThemePainter.drawCursor(
            theme: appearance.theme,
            at: point,
            scale: appearanceScale,
            tint: color,
            alpha: CGFloat(appearance.alpha)
        )
    }

    private func drawBlocked(at point: CGPoint) {
        NSColor.systemRed.withAlphaComponent(0.95).setStroke()
        let stop = NSBezierPath(ovalIn: CGRect(center: point, radius: 17))
        stop.lineWidth = 4
        stop.stroke()

        let slash = NSBezierPath()
        slash.lineWidth = 4
        slash.move(to: CGPoint(x: point.x - 11, y: point.y - 11))
        slash.line(to: CGPoint(x: point.x + 11, y: point.y + 11))
        slash.stroke()
    }

    private func drawHandoff(at point: CGPoint) {
        NSColor.systemOrange.withAlphaComponent(0.95).setFill()
        let diamond = NSBezierPath()
        diamond.move(to: CGPoint(x: point.x, y: point.y + 18))
        diamond.line(to: CGPoint(x: point.x + 18, y: point.y))
        diamond.line(to: CGPoint(x: point.x, y: point.y - 18))
        diamond.line(to: CGPoint(x: point.x - 18, y: point.y))
        diamond.close()
        diamond.fill()
    }

    private func drawLabel(for cursor: VirtualCursorRecord, at point: CGPoint, color: NSColor) {
        guard let label = cursor.taskLabel ?? cursor.lastToolCallID else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color.withAlphaComponent(0.95)
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        text.draw(at: CGPoint(x: point.x + 14, y: point.y + 14))
    }

    private var appearanceScale: CGFloat {
        CGFloat(cursorAppearance.normalized.scale)
    }

    private func localPoint(forScreenPoint point: CGPoint) -> CGPoint {
        VirtualCursorCoordinateConverter.localPoint(fromGlobalTopLeft: point, inScreenFrame: screen.frame)
    }

    private func localRect(forScreenRect rect: CGRect) -> CGRect {
        VirtualCursorCoordinateConverter.localRect(fromGlobalTopLeft: rect, inScreenFrame: screen.frame)
    }
}

private struct AnimatedVirtualCursor {
    var cursor: VirtualCursorRecord
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    var startedAt: Date
    var duration: Double

    func presentationPoint(at date: Date) -> CGPoint? {
        guard let endPoint else {
            return nil
        }
        guard let startPoint else {
            return endPoint
        }
        guard duration > 0 else {
            return endPoint
        }

        let progress = min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
        let eased = easeOutCubic(progress)
        return CGPoint(
            x: startPoint.x + (endPoint.x - startPoint.x) * eased,
            y: startPoint.y + (endPoint.y - startPoint.y) * eased
        )
    }

    private func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
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

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

private extension VirtualCursorPoint {
    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

private extension NSColor {
    convenience init(_ appearance: VirtualCursorAppearance) {
        self.init(
            calibratedRed: appearance.red,
            green: appearance.green,
            blue: appearance.blue,
            alpha: appearance.alpha
        )
    }
}
