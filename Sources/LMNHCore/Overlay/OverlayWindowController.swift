import AppKit

@MainActor
public final class AppKitVirtualCursorRenderer: VirtualCursorRendering {
    private var windows: [ObjectIdentifier: VirtualCursorOverlayPanel]
    private var views: [ObjectIdentifier: VirtualCursorCanvasView]
    private let windowInventory = WindowInventory()

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
                let target = resolveLiveTarget(cursor.target)
                guard let point = target.displayPoint else {
                    return cursor.target.path?.points.contains {
                        VirtualCursorCoordinateConverter.screenFrame(screen.frame, containsGlobalTopLeft: $0.cgPoint)
                    } ?? false
                }

                return VirtualCursorCoordinateConverter.screenFrame(screen.frame, containsGlobalTopLeft: point.cgPoint)
            }
            views[id]?.targetResolver = { [weak self] target in
                self?.resolveLiveTarget(target) ?? target
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

    private func resolveLiveTarget(_ target: VirtualCursorTarget) -> VirtualCursorTarget {
        guard let previousWindowFrame = target.windowFrame,
              let liveWindow = liveWindow(for: target),
              let liveFrame = liveWindow.bounds else {
            return target
        }

        let dx = liveFrame.x - previousWindowFrame.x
        let dy = liveFrame.y - previousWindowFrame.y
        guard dx != 0 || dy != 0 else {
            return target
        }

        return target.offsetBy(dx: dx, dy: dy, liveWindowFrame: liveFrame)
    }

    private func liveWindow(for target: VirtualCursorTarget) -> MacOSWindowInfo? {
        let windows = windowInventory.listWindows()
        if let processIdentifier = target.processIdentifier {
            return windows
                .filter { $0.ownerPID == processIdentifier && $0.layer == 0 && $0.isOnscreen && $0.bounds?.isUsableFrame == true }
                .max { left, right in
                    overlapArea(left.bounds, target.windowFrame) < overlapArea(right.bounds, target.windowFrame)
                }
        }

        guard let appBundleID = target.appBundleID else {
            return nil
        }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == appBundleID }
        let pids = Set(apps.map(\.processIdentifier))
        return windows
            .filter { pids.contains($0.ownerPID) && $0.layer == 0 && $0.isOnscreen && $0.bounds?.isUsableFrame == true }
            .max { left, right in
                overlapArea(left.bounds, target.windowFrame) < overlapArea(right.bounds, target.windowFrame)
            }
    }

    private func overlapArea(_ lhs: LMNHRect?, _ rhs: VirtualCursorFrame?) -> Double {
        guard let lhs, let rhs else { return 0 }
        let xOverlap = max(0, min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x))
        let yOverlap = max(0, min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y))
        return xOverlap * yOverlap
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
    var targetResolver: ((VirtualCursorTarget) -> VirtualCursorTarget)?

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
        let now = Date()
        let incoming = Dictionary(uniqueKeysWithValues: cursors.map { ($0.cursorID, $0) })
        animatedCursors = animatedCursors.filter { incoming[$0.key] != nil }

        for cursor in cursors {
            let resolvedTarget = targetResolver?(cursor.target) ?? cursor.target
            var resolvedCursor = cursor
            resolvedCursor.target = resolvedTarget
            let endPoint = resolvedTarget.displayPoint?.cgPoint
            let previous = animatedCursors[cursor.cursorID]
            let currentPoint = previous?.presentationPoint(at: now) ?? previous?.endPoint ?? endPoint
            let clickPulseStartedAt = clickPulseStart(for: resolvedCursor, previous: previous, now: now)
            animatedCursors[cursor.cursorID] = AnimatedVirtualCursor(
                cursor: resolvedCursor,
                startPoint: currentPoint,
                endPoint: endPoint,
                startedAt: now,
                duration: cursorAppearance.normalized.animationDuration,
                clickPulseStartedAt: clickPulseStartedAt
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
        let liveTarget = targetResolver?(animatedCursor.cursor.target) ?? animatedCursor.cursor.target
        let liveEndPoint = liveTarget.displayPoint?.cgPoint

        guard let point = animatedCursor.presentationPoint(at: now, liveEndPoint: liveEndPoint) else {
            return
        }

        let localPoint = localPoint(forScreenPoint: point)
        drawCursorArrow(
            at: localPoint,
            color: color,
            rotation: motionRotation(for: animatedCursor, liveEndPoint: liveEndPoint, at: now),
            scaleMultiplier: VirtualCursorMotion.clickScale(startedAt: animatedCursor.clickPulseStartedAt, at: now)
        )
    }

    private func drawCursorArrow(
        at point: CGPoint,
        color: NSColor,
        rotation: CGFloat = 0,
        scaleMultiplier: CGFloat = 1
    ) {
        let appearance = cursorAppearance.normalized
        VirtualCursorThemePainter.drawCursor(
            theme: appearance.theme,
            at: point,
            scale: appearanceScale * scaleMultiplier,
            tint: color,
            alpha: CGFloat(appearance.alpha),
            rotation: rotation
        )
    }

    private func motionRotation(
        for animatedCursor: AnimatedVirtualCursor,
        liveEndPoint: CGPoint?,
        at date: Date
    ) -> CGFloat {
        VirtualCursorMotion.rotation(
            start: animatedCursor.startPoint.map(localPoint(forScreenPoint:)),
            end: (liveEndPoint ?? animatedCursor.endPoint).map(localPoint(forScreenPoint:)),
            at: date,
            startedAt: animatedCursor.startedAt,
            duration: animatedCursor.duration
        )
    }

    private func clickPulseStart(
        for cursor: VirtualCursorRecord,
        previous: AnimatedVirtualCursor?,
        now: Date
    ) -> Date? {
        if cursor.state == .pressing, previous?.cursor.updatedAt != cursor.updatedAt {
            return now
        }

        guard let startedAt = previous?.clickPulseStartedAt,
              now.timeIntervalSince(startedAt) < VirtualCursorMotion.clickPulseDuration else {
            return nil
        }

        return startedAt
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
}

private struct AnimatedVirtualCursor {
    var cursor: VirtualCursorRecord
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    var startedAt: Date
    var duration: Double
    var clickPulseStartedAt: Date?

    func presentationPoint(at date: Date, liveEndPoint: CGPoint? = nil) -> CGPoint? {
        let destination = liveEndPoint ?? endPoint
        guard let destination else {
            return nil
        }
        guard let startPoint else {
            return destination
        }
        guard duration > 0 else {
            return destination
        }

        let progress = min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
        let eased = easeOutCubic(progress)
        return CGPoint(
            x: startPoint.x + (destination.x - startPoint.x) * eased,
            y: startPoint.y + (destination.y - startPoint.y) * eased
        )
    }

    private func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
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
