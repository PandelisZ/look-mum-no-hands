import AppKit
import CoreGraphics
import Foundation

public struct MacOSWindowInfo: Codable, Sendable, Identifiable, Equatable {
    public var id: UInt32
    public var ownerPID: Int32
    public var ownerName: String?
    public var title: String?
    public var bounds: LMNHRect?
    public var layer: Int
    public var alpha: Double
    public var isOnscreen: Bool

    public init(
        id: UInt32,
        ownerPID: Int32,
        ownerName: String?,
        title: String?,
        bounds: LMNHRect?,
        layer: Int,
        alpha: Double,
        isOnscreen: Bool
    ) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.isOnscreen = isOnscreen
    }
}

public struct WindowInventory: Sendable {
    public init() {}

    public func listWindows(onscreenOnly: Bool = true) -> [MacOSWindowInfo] {
        let options: CGWindowListOption = onscreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]

        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [MacOSWindowInfo] = []
        for dictionary in rawWindows {
            guard
                let windowNumber = (dictionary[WindowDictionaryKey.number] as? NSNumber)?.uint32Value,
                let ownerPID = (dictionary[WindowDictionaryKey.ownerPID] as? NSNumber)?.int32Value
            else {
                continue
            }

            var rect: CGRect?
            if let boundsDictionary = dictionary[WindowDictionaryKey.bounds] as? NSDictionary {
                rect = CGRect(dictionaryRepresentation: boundsDictionary)
            }

            windows.append(
                MacOSWindowInfo(
                    id: windowNumber,
                    ownerPID: ownerPID,
                    ownerName: dictionary[WindowDictionaryKey.ownerName] as? String,
                    title: dictionary[WindowDictionaryKey.name] as? String,
                    bounds: rect.map { LMNHRect($0) },
                    layer: (dictionary[WindowDictionaryKey.layer] as? NSNumber)?.intValue ?? 0,
                    alpha: (dictionary[WindowDictionaryKey.alpha] as? NSNumber)?.doubleValue ?? 1,
                    isOnscreen: (dictionary[WindowDictionaryKey.isOnscreen] as? NSNumber)?.boolValue ?? onscreenOnly
                )
            )
        }
        return windows
    }

    public func windowCountsByPID(onscreenOnly: Bool = true) -> [Int32: Int] {
        Dictionary(grouping: listWindows(onscreenOnly: onscreenOnly), by: \.ownerPID)
            .mapValues(\.count)
    }
}

private enum WindowDictionaryKey {
    static let number = "kCGWindowNumber"
    static let ownerPID = "kCGWindowOwnerPID"
    static let ownerName = "kCGWindowOwnerName"
    static let name = "kCGWindowName"
    static let bounds = "kCGWindowBounds"
    static let layer = "kCGWindowLayer"
    static let alpha = "kCGWindowAlpha"
    static let isOnscreen = "kCGWindowIsOnscreen"
}
