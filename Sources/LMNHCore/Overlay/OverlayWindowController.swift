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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(cursorAppearanceDidChange(_:)),
            name: VirtualCursorAppearance.didChangeNotification,
            object: nil
        )
    }

    deinit {
        MainActor.assumeIsolated {
            displayTimer?.invalidate()
            DistributedNotificationCenter.default().removeObserver(self)
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
        let now = Date()
        let color = NSColor(cursorAppearance.normalized)

        guard let point = animatedCursor.presentationPoint(at: now) else {
            return
        }

        let localPoint = localPoint(forScreenPoint: point)
        drawCursorArrow(at: localPoint, color: color, rotation: motionRotation(for: animatedCursor, at: now))
    }

    private func drawCursorArrow(at point: CGPoint, color: NSColor, rotation: CGFloat = 0) {
        let appearance = cursorAppearance.normalized
        VirtualCursorThemePainter.drawCursor(
            theme: appearance.theme,
            at: point,
            scale: appearanceScale,
            tint: color,
            alpha: CGFloat(appearance.alpha),
            rotation: rotation
        )
    }

    private func motionRotation(for animatedCursor: AnimatedVirtualCursor, at date: Date) -> CGFloat {
        VirtualCursorMotion.rotation(
            start: animatedCursor.startPoint.map(localPoint(forScreenPoint:)),
            end: animatedCursor.endPoint.map(localPoint(forScreenPoint:)),
            at: date,
            startedAt: animatedCursor.startedAt,
            duration: animatedCursor.duration
        )
    }

    @objc private func cursorAppearanceDidChange(_ notification: Notification) {
        cursorAppearance = VirtualCursorAppearance.load()
        needsDisplay = true
        if !animatedCursors.isEmpty {
            startDisplayTimerIfNeeded()
        }
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

private extension VirtualCursorRecord {
    var displayLabel: String? {
        guard let label = taskLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              !label.hasPrefix("act_"),
              !label.hasPrefix("call_") else {
            return nil
        }
        return label
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
