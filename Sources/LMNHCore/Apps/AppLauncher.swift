import AppKit
import Foundation

public struct AppLaunchResult: Codable, Sendable {
    public var requested: String
    public var status: String
    public var bundleIdentifier: String?
    public var appURL: String?
    public var processIdentifier: Int32?
    public var launchedApplicationName: String?
    public var backgroundRequested: Bool
    public var restoreFocusRequested: Bool
    public var focusPolicy: ActionFocusPolicy
    public var frontmostBefore: String?
    public var frontmostAfterLaunch: String?
    public var frontmostAfterRestore: String?
    public var resolutionMethod: String?
    public var focusRestoreMethod: String?
    public var error: String?
    public var warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case requested
        case status
        case bundleIdentifier = "bundle_identifier"
        case appURL = "app_url"
        case processIdentifier = "process_identifier"
        case launchedApplicationName = "launched_application_name"
        case backgroundRequested = "background_requested"
        case restoreFocusRequested = "restore_focus_requested"
        case focusPolicy = "focus_policy"
        case frontmostBefore = "frontmost_before"
        case frontmostAfterLaunch = "frontmost_after_launch"
        case frontmostAfterRestore = "frontmost_after_restore"
        case resolutionMethod = "resolution_method"
        case focusRestoreMethod = "focus_restore_method"
        case error
        case warnings
    }
}

@MainActor
public struct AppLauncher {
    public init() {}

    public func openApp(
        bundleIdentifier: String?,
        appPath: String?,
        appName: String?,
        background: Bool = true,
        restoreFocus: Bool = true
    ) async -> AppLaunchResult {
        let frontmostBeforeApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBefore = frontmostBeforeApplication?.bundleIdentifier
        let requested = bundleIdentifier ?? appPath ?? appName ?? "<missing app target>"

        let resolution = resolveApplicationURL(
            bundleIdentifier: bundleIdentifier,
            appPath: appPath,
            appName: appName
        )
        guard let appURL = resolution.url else {
            return AppLaunchResult(
                requested: requested,
                status: "failed",
                bundleIdentifier: bundleIdentifier,
                appURL: appPath,
                processIdentifier: nil,
                launchedApplicationName: nil,
                backgroundRequested: background,
                restoreFocusRequested: restoreFocus,
                focusPolicy: .failedBeforeFocusChange,
                frontmostBefore: frontmostBefore,
                frontmostAfterLaunch: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                frontmostAfterRestore: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                resolutionMethod: resolution.method,
                focusRestoreMethod: nil,
                error: "Could not resolve application. Provide bundle_id, app_path, or an app_name LaunchServices can resolve.",
                warnings: []
            )
        }

        do {
            let launchedApplication = try await openApplication(at: appURL, background: background)
            let frontmostAfterLaunch = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            var focusRestoreMethod: String?

            if restoreFocus,
               let frontmostBeforeApplication,
               frontmostAfterLaunch != frontmostBefore {
                _ = frontmostBeforeApplication.activate(options: [])
                focusRestoreMethod = "NSRunningApplication.activate"
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != frontmostBefore {
                    _ = frontmostBeforeApplication.activate(options: [.activateIgnoringOtherApps])
                    focusRestoreMethod = "NSRunningApplication.activate_activateIgnoringOtherApps_deprecated"
                }
            }

            let frontmostAfterRestore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let focusPolicy = focusPolicy(
                background: background,
                restoreFocus: restoreFocus,
                frontmostBefore: frontmostBefore,
                frontmostAfterLaunch: frontmostAfterLaunch,
                frontmostAfterRestore: frontmostAfterRestore
            )

            return AppLaunchResult(
                requested: requested,
                status: "completed",
                bundleIdentifier: launchedApplication?.bundleIdentifier ?? bundleIdentifier,
                appURL: appURL.path,
                processIdentifier: launchedApplication?.processIdentifier,
                launchedApplicationName: launchedApplication?.localizedName,
                backgroundRequested: background,
                restoreFocusRequested: restoreFocus,
                focusPolicy: focusPolicy,
                frontmostBefore: frontmostBefore,
                frontmostAfterLaunch: frontmostAfterLaunch,
                frontmostAfterRestore: frontmostAfterRestore,
                resolutionMethod: resolution.method,
                focusRestoreMethod: focusRestoreMethod,
                error: nil,
                warnings: focusWarnings(
                    focusPolicy: focusPolicy,
                    before: frontmostBefore,
                    afterLaunch: frontmostAfterLaunch,
                    afterRestore: frontmostAfterRestore
                )
            )
        } catch {
            return AppLaunchResult(
                requested: requested,
                status: "failed",
                bundleIdentifier: bundleIdentifier,
                appURL: appURL.path,
                processIdentifier: nil,
                launchedApplicationName: nil,
                backgroundRequested: background,
                restoreFocusRequested: restoreFocus,
                focusPolicy: .failedBeforeFocusChange,
                frontmostBefore: frontmostBefore,
                frontmostAfterLaunch: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                frontmostAfterRestore: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                resolutionMethod: resolution.method,
                focusRestoreMethod: nil,
                error: error.localizedDescription,
                warnings: []
            )
        }
    }

    private func resolveApplicationURL(bundleIdentifier: String?, appPath: String?, appName: String?) -> (url: URL?, method: String?) {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return (url, "NSWorkspace.urlForApplication")
        }

        if let appPath {
            return (URL(fileURLWithPath: appPath), "explicit_app_path")
        }

        if let appName,
           let path = NSWorkspace.shared.fullPath(forApplication: appName) {
            return (URL(fileURLWithPath: path), "NSWorkspace.fullPath_forApplication_deprecated")
        }

        return (nil, nil)
    }

    private func openApplication(at url: URL, background: Bool) async throws -> NSRunningApplication? {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = !background
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: application)
                }
            }
        }
    }

    private func focusPolicy(
        background: Bool,
        restoreFocus: Bool,
        frontmostBefore: String?,
        frontmostAfterLaunch: String?,
        frontmostAfterRestore: String?
    ) -> ActionFocusPolicy {
        if frontmostBefore == frontmostAfterRestore {
            return .noFocusChange
        }

        if background, restoreFocus, frontmostAfterLaunch != frontmostAfterRestore {
            return .temporaryHandoff
        }

        return .focusChangedIntentionally
    }

    private func focusWarnings(
        focusPolicy: ActionFocusPolicy,
        before: String?,
        afterLaunch: String?,
        afterRestore: String?
    ) -> [String] {
        guard focusPolicy != .noFocusChange else {
            return []
        }

        return [
            "frontmost_app_changed_during_launch: \(before ?? "<none>") -> \(afterLaunch ?? "<none>") -> \(afterRestore ?? "<none>")"
        ]
    }
}
