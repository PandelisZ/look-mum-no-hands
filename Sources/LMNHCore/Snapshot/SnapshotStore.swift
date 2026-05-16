import Foundation

public actor SnapshotStore {
    private var snapshots: [String: MacOSSnapshot] = [:]
    private var insertionOrder: [String] = []
    private let limit: Int

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public func store(_ snapshot: MacOSSnapshot) {
        if snapshots[snapshot.id] == nil {
            insertionOrder.append(snapshot.id)
        }
        snapshots[snapshot.id] = snapshot

        while insertionOrder.count > limit {
            let removed = insertionOrder.removeFirst()
            snapshots.removeValue(forKey: removed)
        }
    }

    public func snapshot(id: String) -> MacOSSnapshot? {
        snapshots[id]
    }

    public func latest() -> MacOSSnapshot? {
        insertionOrder.last.flatMap { snapshots[$0] }
    }

    public func retainedSnapshotIds() -> Set<String> {
        Set(insertionOrder)
    }
}
