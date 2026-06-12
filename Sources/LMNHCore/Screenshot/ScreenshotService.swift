import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum ScreenshotImageFormat: String, Codable, Sendable {
    case png
    case jpeg

    public var mimeType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        }
    }
}

public struct ScreenshotRequest: Sendable {
    public var target: String
    public var windowID: UInt32?
    public var displayID: UInt32?
    public var elementFrame: LMNHRect?
    public var elementProcessIdentifier: Int32?
    public var maxWidth: Int
    public var format: ScreenshotImageFormat

    public init(
        target: String = "frontmost_window",
        windowID: UInt32? = nil,
        displayID: UInt32? = nil,
        elementFrame: LMNHRect? = nil,
        elementProcessIdentifier: Int32? = nil,
        maxWidth: Int = 1568,
        format: ScreenshotImageFormat = .png
    ) {
        self.target = target
        self.windowID = windowID
        self.displayID = displayID
        self.elementFrame = elementFrame
        self.elementProcessIdentifier = elementProcessIdentifier
        self.maxWidth = maxWidth
        self.format = format
    }
}

public struct ScreenshotMetadata: Codable, Sendable {
    public var target: String
    public var windowID: UInt32?
    public var windowTitle: String?
    public var appBundleID: String?
    public var displayID: UInt32?
    public var capturedRect: LMNHRect?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scaledDown: Bool
    public var format: String
    public var coordinateSpace: String

    private enum CodingKeys: String, CodingKey {
        case target
        case windowID = "window_id"
        case windowTitle = "window_title"
        case appBundleID = "app_bundle_id"
        case displayID = "display_id"
        case capturedRect = "captured_rect"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case scaledDown = "scaled_down"
        case format
        case coordinateSpace = "coordinate_space"
    }
}

public struct ScreenshotCapture: Sendable {
    public var base64Data: String
    public var metadata: ScreenshotMetadata
}

public enum ScreenshotServiceError: Error, Sendable {
    case permissionDenied
    case noDisplayFound
    case noWindowFound(String)
    case invalidTarget(String)
    case captureFailed(String)
    case encodingFailed

    public var reason: String {
        switch self {
        case .permissionDenied:
            "screen_recording_permission_denied"
        case .noDisplayFound:
            "no_display_found"
        case .noWindowFound(let detail):
            "no_window_found: \(detail)"
        case .invalidTarget(let target):
            "invalid_target: \(target)"
        case .captureFailed(let detail):
            "capture_failed: \(detail)"
        case .encodingFailed:
            "image_encoding_failed"
        }
    }
}

/// Captures pixel screenshots through ScreenCaptureKit without moving the real mouse
/// or changing window focus.
@MainActor
public final class ScreenshotService {
    public init() {}

    public func capture(_ request: ScreenshotRequest) async throws -> ScreenshotCapture {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenshotServiceError.permissionDenied
        }

        // Connect to the window server before any SCContentFilter work; without this,
        // window-targeted filters abort with CGS_REQUIRE_INIT in non-GUI processes.
        _ = CGMainDisplayID()

        let content: SCShareableContent
        do {
            // Include off-screen windows so hidden or occluded apps can still be
            // captured through desktop-independent window filters.
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw ScreenshotServiceError.captureFailed("shareable_content_unavailable: \(error.localizedDescription)")
        }

        switch request.target {
        case "frontmost_window":
            guard let window = frontmostWindow(in: content) else {
                throw ScreenshotServiceError.noWindowFound("no onscreen window for the frontmost application")
            }
            return try await captureWindow(window, request: request)

        case "window":
            guard let windowID = request.windowID else {
                throw ScreenshotServiceError.invalidTarget("target=window requires window_id")
            }
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotServiceError.noWindowFound("window_id \(windowID) is not onscreen")
            }
            return try await captureWindow(window, request: request)

        case "display":
            guard let display = pickDisplay(in: content, displayID: request.displayID, containing: nil) else {
                throw ScreenshotServiceError.noDisplayFound
            }
            return try await captureDisplay(display, content: content, cropRect: nil, request: request)

        case "element":
            guard let frame = request.elementFrame, frame.isUsableFrame else {
                throw ScreenshotServiceError.invalidTarget("target=element requires a resolvable element with a usable frame")
            }
            // Prefer cropping the element's own window so occluded apps still
            // capture their real content instead of whatever covers that screen region.
            if let window = elementWindow(in: content, frame: frame, processIdentifier: request.elementProcessIdentifier) {
                return try await captureWindow(window, cropRect: frame, request: request)
            }
            guard let display = pickDisplay(in: content, displayID: nil, containing: frame) else {
                throw ScreenshotServiceError.noDisplayFound
            }
            return try await captureDisplay(display, content: content, cropRect: frame, request: request)

        default:
            throw ScreenshotServiceError.invalidTarget(request.target)
        }
    }

    private func frontmostWindow(in content: SCShareableContent) -> SCWindow? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return content.windows
            .filter {
                $0.owningApplication?.processID == frontmostPID
                    && $0.isOnScreen
                    && $0.windowLayer == 0
                    && $0.frame.width > 1
                    && $0.frame.height > 1
            }
            .max { left, right in
                left.frame.width * left.frame.height < right.frame.width * right.frame.height
            }
    }

    private func elementWindow(
        in content: SCShareableContent,
        frame: LMNHRect,
        processIdentifier: Int32?
    ) -> SCWindow? {
        guard let processIdentifier else {
            return nil
        }
        return content.windows
            .filter {
                $0.owningApplication?.processID == processIdentifier
                    && $0.windowLayer == 0
                    && intersectionArea($0.frame, frame.cgRect) > 0
            }
            .max { left, right in
                intersectionArea(left.frame, frame.cgRect) < intersectionArea(right.frame, frame.cgRect)
            }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func pickDisplay(
        in content: SCShareableContent,
        displayID: UInt32?,
        containing frame: LMNHRect?
    ) -> SCDisplay? {
        if let displayID {
            return content.displays.first { $0.displayID == displayID }
        }
        if let frame {
            let center = CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
            if let containing = content.displays.first(where: { $0.frame.contains(center) }) {
                return containing
            }
        }
        return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    }

    private func captureWindow(
        _ window: SCWindow,
        cropRect: LMNHRect? = nil,
        request: ScreenshotRequest
    ) async throws -> ScreenshotCapture {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = max(1, CGFloat(filter.pointPixelScale))
        let configuration = makeConfiguration(
            pixelSize: CGSize(
                width: window.frame.width * scale,
                height: window.frame.height * scale
            )
        )

        var image = try await takeScreenshot(filter: filter, configuration: configuration)
        var capturedRect = LMNHRect(window.frame)

        if let cropRect {
            let local = cropRect.cgRect
                .offsetBy(dx: -window.frame.origin.x, dy: -window.frame.origin.y)
                .intersection(CGRect(origin: .zero, size: window.frame.size))
            guard !local.isNull, local.width >= 1, local.height >= 1 else {
                throw ScreenshotServiceError.invalidTarget("element frame does not intersect its window")
            }
            let pixelCrop = CGRect(
                x: local.origin.x * scale,
                y: local.origin.y * scale,
                width: local.width * scale,
                height: local.height * scale
            )
            guard let cropped = image.cropping(to: pixelCrop) else {
                throw ScreenshotServiceError.captureFailed("element crop failed")
            }
            image = cropped
            capturedRect = LMNHRect(
                local.offsetBy(dx: window.frame.origin.x, dy: window.frame.origin.y)
            )
        }

        return try encode(
            image: image,
            request: request,
            metadata: ScreenshotMetadata(
                target: request.target,
                windowID: window.windowID,
                windowTitle: window.title,
                appBundleID: window.owningApplication?.bundleIdentifier,
                displayID: nil,
                capturedRect: capturedRect,
                pixelWidth: 0,
                pixelHeight: 0,
                scaledDown: false,
                format: request.format.rawValue,
                coordinateSpace: "global_display_points"
            )
        )
    }

    private func captureDisplay(
        _ display: SCDisplay,
        content: SCShareableContent,
        cropRect: LMNHRect?,
        request: ScreenshotRequest
    ) async throws -> ScreenshotCapture {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = max(1, CGFloat(filter.pointPixelScale))
        var capturedRect = LMNHRect(display.frame)
        let configuration: SCStreamConfiguration

        if let cropRect {
            // sourceRect is in points relative to the display's own origin.
            let local = CGRect(
                x: cropRect.x - display.frame.origin.x,
                y: cropRect.y - display.frame.origin.y,
                width: cropRect.width,
                height: cropRect.height
            ).intersection(CGRect(origin: .zero, size: display.frame.size))

            guard !local.isNull, local.width >= 1, local.height >= 1 else {
                throw ScreenshotServiceError.invalidTarget("element frame does not intersect display \(display.displayID)")
            }

            configuration = makeConfiguration(pixelSize: CGSize(width: local.width * scale, height: local.height * scale))
            configuration.sourceRect = local
            capturedRect = LMNHRect(
                CGRect(
                    x: local.origin.x + display.frame.origin.x,
                    y: local.origin.y + display.frame.origin.y,
                    width: local.width,
                    height: local.height
                )
            )
        } else {
            configuration = makeConfiguration(
                pixelSize: CGSize(
                    width: display.frame.width * scale,
                    height: display.frame.height * scale
                )
            )
        }

        let image = try await takeScreenshot(filter: filter, configuration: configuration)
        return try encode(
            image: image,
            request: request,
            metadata: ScreenshotMetadata(
                target: request.target,
                windowID: nil,
                windowTitle: nil,
                appBundleID: nil,
                displayID: display.displayID,
                capturedRect: capturedRect,
                pixelWidth: 0,
                pixelHeight: 0,
                scaledDown: false,
                format: request.format.rawValue,
                coordinateSpace: "global_display_points"
            )
        )
    }

    private func makeConfiguration(pixelSize: CGSize) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(pixelSize.width.rounded()))
        configuration.height = max(1, Int(pixelSize.height.rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return configuration
    }

    private func takeScreenshot(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw ScreenshotServiceError.captureFailed(error.localizedDescription)
        }
    }

    private func encode(
        image: CGImage,
        request: ScreenshotRequest,
        metadata: ScreenshotMetadata
    ) throws -> ScreenshotCapture {
        var metadata = metadata
        var outputImage = image
        metadata.scaledDown = false

        if request.maxWidth > 0, image.width > request.maxWidth {
            if let scaled = downscale(image, toWidth: request.maxWidth) {
                outputImage = scaled
                metadata.scaledDown = true
            }
        }

        metadata.pixelWidth = outputImage.width
        metadata.pixelHeight = outputImage.height

        let bitmap = NSBitmapImageRep(cgImage: outputImage)
        let fileType: NSBitmapImageRep.FileType = request.format == .jpeg ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] =
            request.format == .jpeg ? [.compressionFactor: 0.82] : [:]

        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            throw ScreenshotServiceError.encodingFailed
        }

        return ScreenshotCapture(base64Data: data.base64EncodedString(), metadata: metadata)
    }

    private func downscale(_ image: CGImage, toWidth maxWidth: Int) -> CGImage? {
        let ratio = Double(maxWidth) / Double(image.width)
        let width = maxWidth
        let height = max(1, Int((Double(image.height) * ratio).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
