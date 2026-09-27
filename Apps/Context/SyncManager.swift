import ContextDomain
import Foundation

/// Optional iCloud sync through the user's own iCloud (NSUbiquitousKeyValueStore).
/// Off by default. Local JSON stays the source of truth; sync only merges
/// last-writer-wins records in and pushes local state out.
/// No Context account, no Context server.
@MainActor
final class SyncManager {
    static let shared = SyncManager()
    private var timer: Timer?

    enum Status: Equatable {
        case off
        case noICloud
        case idle(lastSync: Date?)
        case syncing
        case error(String)
    }

    private(set) var status: Status = .off

    private init() {}

    var isEnabled: Bool {
        get { ContextSettings.shared.iCloudSyncEnabled }
        set {
            ContextSettings.shared.iCloudSyncEnabled = newValue
            ContextSettings.shared.save()
            if newValue { start() } else { stop() }
        }
    }

    func start() {
        guard ContextSettings.shared.iCloudSyncEnabled else {
            status = .off
            return
        }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            status = .noICloud
            return
        }
        status = .idle(lastSync: ContextSettings.shared.lastSyncAt)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        sync()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        status = .off
    }

    @objc private func storeDidChange(_ note: Notification) {
        sync()
    }

    /// Pushes local notes, pulls remote, merges last-writer-wins.
    /// `store` callbacks keep this testable without importing ContextStore.
    func sync(
        localNotes: () -> [ContextNote] = { NoteStoreAccessor.live() },
        applyMerged: (NSArray) -> Void = { _ in }
    ) {
        guard ContextSettings.shared.iCloudSyncEnabled else {
            status = .off
            return
        }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            status = .noICloud
            return
        }
        status = .syncing
        let store = NSUbiquitousKeyValueStore.default
        // Pull first.
        var remote: [ContextNote] = []
        do {
            var chunks: [Data] = []
            var i = 0
            while let data = store.data(forKey: "\(SyncPayload.kvKey).\(i)") {
                chunks.append(data)
                i += 1
            }
            if !chunks.isEmpty {
                remote = try SyncPayload.decode(SyncPayload.join(chunks))
            }
        } catch {
            status = .error("Could not read iCloud data.")
            return
        }
        let local = localNotes()
        let (merged, changed) = SyncPayload.merge(local: local, remote: remote)
        if changed {
            applyMerged(merged as NSArray)
        }
        // Push merged state back out.
        do {
            let data = try SyncPayload.encode(changed ? merged : local)
            let chunks = SyncPayload.chunk(data)
            for (i, chunk) in chunks.enumerated() {
                store.set(chunk, forKey: "\(SyncPayload.kvKey).\(i)")
            }
            // Clear stale chunk keys from a previously larger payload.
            var i = chunks.count
            while store.object(forKey: "\(SyncPayload.kvKey).\(i)") != nil {
                store.removeObject(forKey: "\(SyncPayload.kvKey).\(i)")
                i += 1
            }
            store.synchronize()
            ContextSettings.shared.lastSyncAt = Date()
            ContextSettings.shared.save()
            status = .idle(lastSync: ContextSettings.shared.lastSyncAt)
        } catch {
            status = .error("Could not write iCloud data.")
        }
    }

    func statusText() -> String {
        switch status {
        case .off: return "iCloud sync is off. Notes stay on this Mac."
        case .noICloud: return "Not signed into iCloud on this Mac."
        case .idle(let last):
            if let last {
                let mins = Int(Date().timeIntervalSince(last) / 60)
                return mins < 1 ? "Synced just now." : "Last synced \(mins)m ago."
            }
            return "iCloud ready. First sync pending."
        case .syncing: return "Syncing…"
        case .error(let msg): return msg
        }
    }
}

/// Thin accessor so SyncManager stays decoupled from NoteStore's init.
private enum NoteStoreAccessor {
    nonisolated(unsafe) static var provider: (() -> [ContextNote])?
    static func live() -> [ContextNote] { provider?() ?? [] }
}
