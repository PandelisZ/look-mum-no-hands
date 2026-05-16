import Foundation

public struct RegisteredElement: @unchecked Sendable {
    public var snapshotId: String
    public var record: AccessibilityElementRecord
    public var handle: AXElementHandle

    public init(snapshotId: String, record: AccessibilityElementRecord, handle: AXElementHandle) {
        self.snapshotId = snapshotId
        self.record = record
        self.handle = handle
    }
}

public final class ElementRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var elementsBySnapshot: [String: [String: RegisteredElement]] = [:]

    public init() {}

    public func store(snapshotId: String, elements: [RegisteredElement]) {
        lock.withLock {
            elementsBySnapshot[snapshotId] = Dictionary(uniqueKeysWithValues: elements.map { ($0.record.id, $0) })
        }
    }

    public func resolve(snapshotId: String, elementId: String) -> RegisteredElement? {
        lock.withLock {
            elementsBySnapshot[snapshotId]?[elementId]
        }
    }

    public func records(snapshotId: String) -> [AccessibilityElementRecord] {
        lock.withLock {
            Array(elementsBySnapshot[snapshotId]?.values.map(\.record) ?? [])
        }
        .sorted { $0.id < $1.id }
    }

    public func removeSnapshots(except retainedSnapshotIds: Set<String>) {
        lock.withLock {
            elementsBySnapshot = elementsBySnapshot.filter { retainedSnapshotIds.contains($0.key) }
        }
    }
}
