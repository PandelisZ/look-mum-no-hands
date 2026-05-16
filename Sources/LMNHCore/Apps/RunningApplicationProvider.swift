import AppKit
import Foundation

public struct RunningApplicationInfo: Codable, Sendable, Identifiable, Equatable {
    public var id: Int32 { processIdentifier }

    public var bundleIdentifier: String?
    public var localizedName: String
    public var processIdentifier: Int32
    public var executablePath: String?
    public var activationPolicy: String
    public var isFrontmost: Bool
    public var hasWindows: Bool

    public init(
        bundleIdentifier: String?,
        localizedName: String,
        processIdentifier: Int32,
        executablePath: String?,
        activationPolicy: String,
        isFrontmost: Bool,
        hasWindows: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.executablePath = executablePath
        self.activationPolicy = activationPolicy
        self.isFrontmost = isFrontmost
        self.hasWindows = hasWindows
    }
}

@MainActor
public struct RunningApplicationProvider {
    private let windowInventory: WindowInventory

    public init(windowInventory: WindowInventory = WindowInventory()) {
        self.windowInventory = windowInventory
    }

    public func listRunningApplications(includeBackgroundAgents: Bool = true) -> [RunningApplicationInfo] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let windowCounts = windowInventory.windowCountsByPID()

        return NSWorkspace.shared.runningApplications.compactMap { application in
            if !includeBackgroundAgents && application.activationPolicy == .prohibited && windowCounts[application.processIdentifier] == nil {
                return nil
            }

            return RunningApplicationInfo(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName ?? application.bundleIdentifier ?? "pid \(application.processIdentifier)",
                processIdentifier: application.processIdentifier,
                executablePath: application.executableURL?.path,
                activationPolicy: Self.describe(application.activationPolicy),
                isFrontmost: application.processIdentifier == frontmostPID,
                hasWindows: (windowCounts[application.processIdentifier] ?? 0) > 0
            )
        }
    }

    public func frontmostApplication() -> RunningApplicationInfo? {
        listRunningApplications().first(where: \.isFrontmost)
    }

    private static func describe(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            "regular"
        case .accessory:
            "accessory"
        case .prohibited:
            "prohibited"
        @unknown default:
            "unknown"
        }
    }
}
