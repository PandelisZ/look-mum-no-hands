import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

/// Delivers synthesized scroll and keyboard events to a specific process/window using
/// `CGEvent.postToPid`. Unlike posting to the global HID tap, this never moves the real
/// mouse pointer and does not require activating (focusing) the target app.
public struct TargetedEventDispatcher: Sendable {
    public let targetProcessIdentifier: Int32
    public let windowNumber: UInt32
    public let windowFrame: CGRect

    public init(targetProcessIdentifier: Int32, windowNumber: UInt32, windowFrame: CGRect) {
        self.targetProcessIdentifier = targetProcessIdentifier
        self.windowNumber = windowNumber
        self.windowFrame = windowFrame
    }

    public enum ScrollDirection: String, Sendable {
        case up
        case down
        case left
        case right
    }

    @discardableResult
    public func scroll(atScreenPoint screenPoint: CGPoint, direction: ScrollDirection, pages: Double) -> Bool {
        let lineDelta: Int32 = 12
        let delta: (x: Int32, y: Int32) = switch direction {
        case .up: (0, lineDelta)
        case .down: (0, -lineDelta)
        case .left: (lineDelta, 0)
        case .right: (-lineDelta, 0)
        }

        let ticks = max(1, Int((max(0.05, pages) * 8).rounded(.up)))
        var posted = false

        for _ in 0 ..< ticks {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: delta.y,
                wheel2: delta.x,
                wheel3: 0
            ) else {
                continue
            }
            event.location = screenPoint
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetProcessIdentifier))
            event.setWindowAddressingFields(windowNumber: windowNumber)
            TargetedWindowLocation.setPoint(windowLocalQuartzPoint(from: screenPoint), on: event)
            event.postToPid(targetProcessIdentifier)
            posted = true
            usleep(8_000)
        }

        return posted
    }

    public func typeUnicode(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        for cluster in text {
            let units = Array(String(cluster).utf16)
            units.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress, buffer.count > 0,
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    return
                }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                postKeyEvent(down)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                postKeyEvent(up)
            }
            usleep(1_500)
        }
    }

    @discardableResult
    public func press(keyCombination raw: String) -> KeyPressOutcome {
        let combo: KeyCombination
        do {
            combo = try KeyCombination.parse(raw)
        } catch {
            return .unsupported(raw)
        }

        let source = CGEventSource(stateID: .privateState)
        let combinedFlags = combo.modifiers.reduce(into: CGEventFlags()) { $0.formUnion($1.flags) }

        for modifier in combo.modifiers {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: modifier.virtualKey, keyDown: true) {
                event.flags = modifier.flags
                postKeyEvent(event)
            }
        }

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) else {
            return .failed
        }
        down.flags = combinedFlags
        postKeyEvent(down)
        up.flags = combinedFlags
        postKeyEvent(up)

        var remainingFlags = combinedFlags
        for modifier in combo.modifiers.reversed() {
            remainingFlags.subtract(modifier.flags)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: modifier.virtualKey, keyDown: false) {
                event.flags = remainingFlags
                postKeyEvent(event)
            }
        }

        return .delivered(canonical: combo.canonical)
    }

    private func postKeyEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetProcessIdentifier))
        event.setWindowAddressingFields(windowNumber: windowNumber)
        event.postToPid(targetProcessIdentifier)
    }

    private func windowLocalQuartzPoint(from screenPoint: CGPoint) -> CGPoint {
        guard windowFrame.width > 0, windowFrame.height > 0 else {
            return screenPoint
        }
        let localX = screenPoint.x - windowFrame.minX
        let localTopDown = screenPoint.y - windowFrame.minY
        return CGPoint(x: localX, y: windowFrame.height - localTopDown)
    }
}

public enum KeyPressOutcome: Sendable, Equatable {
    case delivered(canonical: String)
    case unsupported(String)
    case failed
}

private extension CGEvent {
    // Private CGEvent fields used with postToPid to address a concrete target window
    // without routing through the global HID event tap.
    static let targetWindowNumberField = CGEventField(rawValue: 51)
    static let privateWindowRoutingField = CGEventField(rawValue: 58)

    func setWindowAddressingFields(windowNumber: UInt32) {
        guard windowNumber != 0 else { return }
        if let field = Self.targetWindowNumberField {
            setIntegerValueField(field, value: Int64(windowNumber))
        }
        if let field = Self.privateWindowRoutingField {
            setIntegerValueField(field, value: 1)
        }
    }
}

/// Bridges to the private `CGEventSetWindowLocation` so synthesized events carry a
/// window-local coordinate, improving hit-testing inside the addressed window.
enum TargetedWindowLocation {
    private typealias SetWindowLocationFn = @convention(c) (CGEvent, CGPoint) -> Void

    private static let setWindowLocation: SetWindowLocationFn? = {
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetWindowLocationFn.self)
    }()

    @discardableResult
    static func setPoint(_ point: CGPoint, on event: CGEvent) -> Bool {
        guard let setWindowLocation else { return false }
        setWindowLocation(event, point)
        return true
    }
}

struct KeyCombination {
    let modifiers: [KeyModifier]
    let keyCode: CGKeyCode
    let canonical: String

    static func parse(_ raw: String) throws -> KeyCombination {
        let segments = raw
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let final = segments.last else {
            throw KeyParseError.unsupported(raw)
        }

        let modifiers = try segments.dropLast().map(KeyModifier.init(token:))
        let keyCode = try Self.keyCode(for: final)
        let canonical = (modifiers.map(\.token) + [final]).joined(separator: "+")
        return KeyCombination(modifiers: modifiers, keyCode: keyCode, canonical: canonical)
    }

    private static func keyCode(for token: String) throws -> CGKeyCode {
        if token.count == 1, let scalar = token.unicodeScalars.first {
            switch scalar {
            case "a" ... "z": return alphaKeyCodes[String(scalar)]!
            case "0" ... "9": return digitKeyCodes[String(scalar)]!
            default: break
            }
        }
        guard let keyCode = namedKeyCodes[token] else {
            throw KeyParseError.unsupported(token)
        }
        return keyCode
    }
}

enum KeyParseError: Error {
    case unsupported(String)
}

struct KeyModifier {
    let token: String
    let flags: CGEventFlags
    let virtualKey: CGKeyCode

    init(token: String) throws {
        switch token {
        case "shift":
            self.init(token: "shift", flags: .maskShift, virtualKey: CGKeyCode(kVK_Shift))
        case "control", "ctrl":
            self.init(token: "control", flags: .maskControl, virtualKey: CGKeyCode(kVK_Control))
        case "option", "alt":
            self.init(token: "option", flags: .maskAlternate, virtualKey: CGKeyCode(kVK_Option))
        case "command", "cmd", "super", "meta":
            self.init(token: "command", flags: .maskCommand, virtualKey: CGKeyCode(kVK_Command))
        case "fn", "function":
            self.init(token: "fn", flags: .maskSecondaryFn, virtualKey: 0)
        default:
            throw KeyParseError.unsupported(token)
        }
    }

    private init(token: String, flags: CGEventFlags, virtualKey: CGKeyCode) {
        self.token = token
        self.flags = flags
        self.virtualKey = virtualKey
    }
}

private let alphaKeyCodes: [String: CGKeyCode] = [
    "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
    "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
    "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
    "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
    "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
    "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
    "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
    "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
    "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
]

private let digitKeyCodes: [String: CGKeyCode] = [
    "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
    "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
    "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
    "9": CGKeyCode(kVK_ANSI_9),
]

private let namedKeyCodes: [String: CGKeyCode] = [
    "space": CGKeyCode(kVK_Space), "tab": CGKeyCode(kVK_Tab),
    "return": CGKeyCode(kVK_Return), "enter": CGKeyCode(kVK_Return),
    "escape": CGKeyCode(kVK_Escape), "esc": CGKeyCode(kVK_Escape),
    "delete": CGKeyCode(kVK_Delete), "backspace": CGKeyCode(kVK_Delete),
    "forward-delete": CGKeyCode(kVK_ForwardDelete), "forwarddelete": CGKeyCode(kVK_ForwardDelete),
    "left": CGKeyCode(kVK_LeftArrow), "right": CGKeyCode(kVK_RightArrow),
    "up": CGKeyCode(kVK_UpArrow), "down": CGKeyCode(kVK_DownArrow),
    "home": CGKeyCode(kVK_Home), "end": CGKeyCode(kVK_End),
    "pageup": CGKeyCode(kVK_PageUp), "pagedown": CGKeyCode(kVK_PageDown),
    "f1": CGKeyCode(kVK_F1), "f2": CGKeyCode(kVK_F2), "f3": CGKeyCode(kVK_F3),
    "f4": CGKeyCode(kVK_F4), "f5": CGKeyCode(kVK_F5), "f6": CGKeyCode(kVK_F6),
    "f7": CGKeyCode(kVK_F7), "f8": CGKeyCode(kVK_F8), "f9": CGKeyCode(kVK_F9),
    "f10": CGKeyCode(kVK_F10), "f11": CGKeyCode(kVK_F11), "f12": CGKeyCode(kVK_F12),
]
