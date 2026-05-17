import ApplicationServices
import AppKit
import Foundation

public struct AXClient: Sendable {
    private let valueBridge = AXValueBridge()

    public init() {}

    public func systemWideElement() -> AXElementHandle {
        AXElementHandle(AXUIElementCreateSystemWide())
    }

    public func applicationElement(processIdentifier: Int32) -> AXElementHandle {
        AXElementHandle(AXUIElementCreateApplication(processIdentifier))
    }

    @MainActor
    public func frontmostApplicationElement() -> AXElementHandle? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return applicationElement(processIdentifier: processIdentifier)
    }

    public func attributeNames(of element: AXElementHandle) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element.raw, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    public func parameterizedAttributeNames(of element: AXElementHandle) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element.raw, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    public func actionNames(of element: AXElementHandle) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element.raw, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    public func attributeValue(_ attribute: String, of element: AXElementHandle) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element.raw, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    public func stringAttribute(_ attribute: String, of element: AXElementHandle) -> String? {
        attributeValue(attribute, of: element) as? String
    }

    public func boolAttribute(_ attribute: String, of element: AXElementHandle) -> Bool? {
        if let bool = attributeValue(attribute, of: element) as? Bool {
            return bool
        }
        return (attributeValue(attribute, of: element) as? NSNumber)?.boolValue
    }

    public func intAttribute(_ attribute: String, of element: AXElementHandle) -> Int? {
        (attributeValue(attribute, of: element) as? NSNumber)?.intValue
    }

    public func arrayAttribute(_ attribute: String, of element: AXElementHandle) -> [AXElementHandle] {
        guard let children = attributeValue(attribute, of: element) as? [AXUIElement] else {
            return []
        }
        return children.map(AXElementHandle.init)
    }

    public func rectAttribute(_ attribute: String, of element: AXElementHandle) -> CGRect? {
        valueBridge.rect(from: attributeValue(attribute, of: element))
    }

    public func pointAttribute(_ attribute: String, of element: AXElementHandle) -> CGPoint? {
        valueBridge.point(from: attributeValue(attribute, of: element))
    }

    public func sizeAttribute(_ attribute: String, of element: AXElementHandle) -> CGSize? {
        valueBridge.size(from: attributeValue(attribute, of: element))
    }

    public func frame(of element: AXElementHandle) -> CGRect? {
        if let frame = rectAttribute("AXFrame", of: element) {
            return frame
        }

        guard
            let position = pointAttribute(AXNames.Attribute.position, of: element),
            let size = sizeAttribute(AXNames.Attribute.size, of: element)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    public func settableAttributes(of element: AXElementHandle, within attributeNames: [String]? = nil) -> [String] {
        let names = attributeNames ?? self.attributeNames(of: element)
        return names.filter { name in
            isAttributeSettable(name, of: element)
        }
    }

    public func isAttributeSettable(_ attribute: String, of element: AXElementHandle) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element.raw, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    public func rangeAttribute(_ attribute: String, of element: AXElementHandle) -> CFRange? {
        valueBridge.range(from: attributeValue(attribute, of: element))
    }

    @discardableResult
    public func performAction(_ action: String, on element: AXElementHandle) -> AXError {
        AXUIElementPerformAction(element.raw, action as CFString)
    }

    @discardableResult
    public func setStringValue(_ value: String, on element: AXElementHandle, attribute: String = AXNames.Attribute.value) -> AXError {
        AXUIElementSetAttributeValue(element.raw, attribute as CFString, value as CFString)
    }

    @discardableResult
    public func setRangeValue(_ value: CFRange, on element: AXElementHandle, attribute: String = AXNames.Attribute.selectedTextRange) -> AXError {
        guard let axValue = valueBridge.axValue(from: value) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(element.raw, attribute as CFString, axValue)
    }

    public func elementAtPosition(_ point: CGPoint, processIdentifier: Int32? = nil) -> Result<AXElementHandle, AXErrorInfo> {
        let root = processIdentifier.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &element)
        guard error == .success, let element else {
            return .failure(AXErrorInfo(error))
        }
        return .success(AXElementHandle(element))
    }
}
