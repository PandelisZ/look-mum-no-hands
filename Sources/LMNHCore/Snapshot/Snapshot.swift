import AppKit
import Foundation

public enum SnapshotMode: String, Codable, Sendable {
    case summary
    case standard
    case full
}

public struct MacOSSnapshotRequest: Codable, Sendable {
    public var mode: SnapshotMode
    public var targetBundleIdentifier: String?
    public var targetProcessIdentifier: Int32?
    public var maxDepth: Int
    public var maxNodes: Int
    public var includeBackgroundAgents: Bool

    public init(
        mode: SnapshotMode = .standard,
        targetBundleIdentifier: String? = nil,
        targetProcessIdentifier: Int32? = nil,
        maxDepth: Int = 8,
        maxNodes: Int = 750,
        includeBackgroundAgents: Bool = true
    ) {
        self.mode = mode
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetProcessIdentifier = targetProcessIdentifier
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
        self.includeBackgroundAgents = includeBackgroundAgents
    }
}

public struct MacOSSnapshot: Codable, Sendable {
    public var id: String
    public var capturedAt: Date
    public var mode: SnapshotMode
    public var permissionStatus: MacOSPermissionStatus
    public var frontmostApplication: RunningApplicationInfo?
    public var targetApplication: RunningApplicationInfo?
    public var applications: [RunningApplicationInfo]
    public var windows: [MacOSWindowInfo]
    public var virtualCursors: [VirtualCursorRecord]
    public var accessibilityTree: [AccessibilityElementRecord]
    public var focusedElementId: String?
    public var focusedWindowElementId: String?
    public var coordinateSpace: String
    public var warnings: [String]

    public init(
        id: String,
        capturedAt: Date,
        mode: SnapshotMode,
        permissionStatus: MacOSPermissionStatus,
        frontmostApplication: RunningApplicationInfo?,
        targetApplication: RunningApplicationInfo?,
        applications: [RunningApplicationInfo],
        windows: [MacOSWindowInfo],
        virtualCursors: [VirtualCursorRecord] = [],
        accessibilityTree: [AccessibilityElementRecord],
        focusedElementId: String?,
        focusedWindowElementId: String?,
        coordinateSpace: String = "global_display_points",
        warnings: [String]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.mode = mode
        self.permissionStatus = permissionStatus
        self.frontmostApplication = frontmostApplication
        self.targetApplication = targetApplication
        self.applications = applications
        self.windows = windows
        self.virtualCursors = virtualCursors
        self.accessibilityTree = accessibilityTree
        self.focusedElementId = focusedElementId
        self.focusedWindowElementId = focusedWindowElementId
        self.coordinateSpace = coordinateSpace
        self.warnings = warnings
    }
}

@MainActor
public final class SnapshotService {
    public let elementRegistry: ElementRegistry

    private let permissionReader: PermissionStatusReader
    private let applicationProvider: RunningApplicationProvider
    private let windowInventory: WindowInventory
    private let axClient: AXClient
    private let treeBuilder: AXTreeBuilder

    public init(
        elementRegistry: ElementRegistry = ElementRegistry(),
        permissionReader: PermissionStatusReader = PermissionStatusReader(),
        windowInventory: WindowInventory = WindowInventory(),
        axClient: AXClient = AXClient(),
        treeBuilder: AXTreeBuilder = AXTreeBuilder()
    ) {
        self.elementRegistry = elementRegistry
        self.permissionReader = permissionReader
        self.windowInventory = windowInventory
        self.axClient = axClient
        self.treeBuilder = treeBuilder
        self.applicationProvider = RunningApplicationProvider(windowInventory: windowInventory)
    }

    public func capture(_ request: MacOSSnapshotRequest = MacOSSnapshotRequest()) -> MacOSSnapshot {
        let snapshotId = Self.makeSnapshotId()
        let permissionStatus = permissionReader.current()
        let applications = applicationProvider.listRunningApplications(includeBackgroundAgents: request.includeBackgroundAgents)
        let windows = windowInventory.listWindows()
        let frontmostApplication = applications.first(where: \.isFrontmost)
        let targetApplication = selectTargetApplication(from: applications, request: request, frontmostApplication: frontmostApplication)

        var accessibilityTree: [AccessibilityElementRecord] = []
        var registryEntries: [RegisteredElement] = []
        var warnings: [String] = []

        if !permissionStatus.accessibilityTrusted {
            warnings.append("Accessibility permission is not granted; AX tree may be empty.")
        }

        if let targetApplication {
            let root = axClient.applicationElement(processIdentifier: targetApplication.processIdentifier)

            if permissionStatus.accessibilityTrusted {
                let newlyActivated = EnhancedAccessibilityActivator.shared.activateIfNeeded(
                    processIdentifier: targetApplication.processIdentifier,
                    applicationElement: root
                )
                if newlyActivated {
                    // Chromium/Electron apps populate their AX tree asynchronously after the
                    // enhanced-accessibility attributes are set; give it a brief moment.
                    Thread.sleep(forTimeInterval: 0.35)
                    warnings.append("Enabled enhanced accessibility for \(targetApplication.localizedName ?? "target app"); re-run macos_snapshot if the tree looks incomplete.")
                }
            }

            let result = treeBuilder.buildApplicationTree(
                root: root,
                snapshotId: snapshotId,
                processIdentifier: targetApplication.processIdentifier,
                bundleIdentifier: targetApplication.bundleIdentifier,
                appName: targetApplication.localizedName,
                options: AXTreeBuildOptions(
                    mode: request.mode,
                    maxDepth: request.maxDepth,
                    maxNodes: request.maxNodes
                )
            )
            accessibilityTree = result.records
            registryEntries = result.registryEntries
            warnings.append(contentsOf: result.warnings)
        } else {
            warnings.append("No target application found for snapshot.")
        }

        elementRegistry.store(snapshotId: snapshotId, elements: registryEntries)

        return MacOSSnapshot(
            id: snapshotId,
            capturedAt: Date(),
            mode: request.mode,
            permissionStatus: permissionStatus,
            frontmostApplication: frontmostApplication,
            targetApplication: targetApplication,
            applications: applications,
            windows: windows,
            accessibilityTree: accessibilityTree,
            focusedElementId: accessibilityTree.first(where: { $0.focused == true })?.id,
            focusedWindowElementId: accessibilityTree.first(where: { $0.role == AXNames.Role.window && $0.focused == true })?.id,
            warnings: warnings
        )
    }

    private func selectTargetApplication(
        from applications: [RunningApplicationInfo],
        request: MacOSSnapshotRequest,
        frontmostApplication: RunningApplicationInfo?
    ) -> RunningApplicationInfo? {
        if let processIdentifier = request.targetProcessIdentifier {
            return applications.first { $0.processIdentifier == processIdentifier }
        }

        if let bundleIdentifier = request.targetBundleIdentifier {
            return applications.first { $0.bundleIdentifier == bundleIdentifier }
        }

        return frontmostApplication
    }

    private static func makeSnapshotId() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "snap_\(timestamp)_\(UUID().uuidString.prefix(8).lowercased())"
    }
}
