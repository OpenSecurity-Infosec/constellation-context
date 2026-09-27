import CloudKit
import ContextDomain
import Foundation

/// Optional iCloud sync through the user's own iCloud. Off by default.
/// Transport: CloudKit private database when the container is reachable,
/// KVS chunk fallback otherwise. Local JSON stays the source of truth;
/// last-writer-wins per note id on `updatedAt`.
/// No Context account, no Context server.
@MainActor
final class SyncManager {
    static let shared = SyncManager()
    private var timer: Timer?
    private var ckToken: CKServerChangeToken?
    private var ckZone: CKRecordZone?
    private let containerID = "iCloud.app.constellation.Context"

    enum Status: Equatable {
        case off
        case noICloud
        case idle(lastSync: Date?)
        case syncing
        case error(String)
    }

    enum Transport: Equatable {
        case cloudKit
        case kvs
        case none
    }

    private(set) var status: Status = .off
    private(set) var transport: Transport = .none

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
        localNotes: @escaping () -> [ContextNote] = { NoteStoreAccessor.live() },
        applyMerged: @escaping (NSArray) -> Void = { _ in }
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
        Task { [weak self] in
            await self?.syncViaCloudKit(localNotes: localNotes, applyMerged: applyMerged)
        }
    }

    /// CloudKit private-DB sync with KVS fallback when the container is
    /// unreachable (no entitlement, offline, tests).
    private func syncViaCloudKit(
        localNotes: @escaping () -> [ContextNote],
        applyMerged: @escaping (NSArray) -> Void
    ) async {
        let container = CKContainer(identifier: containerID)
        do {
            let account = try await container.accountStatus()
            guard account == .available else {
                transport = .kvs
                syncViaKVS(localNotes: localNotes, applyMerged: applyMerged)
                return
            }
        } catch {
            transport = .kvs
            syncViaKVS(localNotes: localNotes, applyMerged: applyMerged)
            return
        }
        transport = .cloudKit
        let db = container.privateCloudDatabase
        let zoneID = CloudKitSync.zoneID(covering: containerID)
        do {
            // Ensure the zone exists.
            if ckZone == nil {
                let zone = try await db.recordZone(for: zoneID)
                ckZone = zone
            }
        } catch {
            // Fetch-or-create: save a zone then continue.
            do {
                ckZone = try await db.save(CKRecordZone(zoneID: zoneID))
            } catch {
                transport = .kvs
                syncViaKVS(localNotes: localNotes, applyMerged: applyMerged)
                return
            }
        }
        // Pull changes, then push local state.
        do {
            let local = localNotes()
            var remote: [ContextNote] = []
            let changes = try await fetchChanges(db: db, zoneID: zoneID)
            remote = changes.compactMap { CloudKitSync.note(from: $0) }
            let (merged, changed) = SyncPayload.merge(local: local, remote: remote)
            if changed {
                await MainActor.run { applyMerged(merged as NSArray) }
            }
            try await pushAll(db: db, zoneID: zoneID, notes: changed ? merged : local)
            ContextSettings.shared.lastSyncAt = Date()
            ContextSettings.shared.save()
            status = .idle(lastSync: ContextSettings.shared.lastSyncAt)
        } catch {
            // Safe fallback: keep KVS in the loop rather than failing.
            transport = .kvs
            syncViaKVS(localNotes: localNotes, applyMerged: applyMerged)
        }
    }

    private func fetchChanges(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var token = ckToken
        var more = true
        while more {
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: token)
            let op = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            var batch: [CKRecord] = []
            var newToken: CKServerChangeToken?
            op.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { batch.append(record) }
            }
            op.recordZoneChangeTokensUpdatedBlock = { _, token, _ in newToken = token }
            op.recordZoneFetchResultBlock = { _, result in
                if case .success(let (token, _, _)) = result { newToken = token }
            }
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let err): cont.resume(throwing: err)
                    }
                }
                db.add(op)
            }
            out += batch
            if let newToken { token = newToken }
            more = false
        }
        ckToken = token
        return out
    }

    private func pushAll(db: CKDatabase, zoneID: CKRecordZone.ID, notes: [ContextNote]) async throws {
        let records = notes.map { CloudKitSync.record(for: $0, zoneID: zoneID) }
        for chunk in records.chunked(into: 200) {
            let op = CKModifyRecordsOperation(recordsToSave: chunk, recordIDsToDelete: [])
            op.savePolicy = .changedKeys
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let err): cont.resume(throwing: err)
                    }
                }
                db.add(op)
            }
        }
    }

    private func syncViaKVS(
        localNotes: () -> [ContextNote],
        applyMerged: (NSArray) -> Void
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
        let via: String = switch transport {
        case .cloudKit: " via iCloud (CloudKit)"
        case .kvs: " via iCloud (key-value)"
        case .none: ""
        }
        switch status {
        case .off: return "iCloud sync is off. Notes stay on this Mac."
        case .noICloud: return "Not signed into iCloud on this Mac."
        case .idle(let last):
            if let last {
                let mins = Int(Date().timeIntervalSince(last) / 60)
                return (mins < 1 ? "Synced just now" : "Last synced \(mins)m ago") + "\(via)."
            }
            return "iCloud ready. First sync pending."
        case .syncing: return "Syncing…"
        case .error(let msg): return msg
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// Thin accessor so SyncManager stays decoupled from NoteStore's init.
private enum NoteStoreAccessor {
    nonisolated(unsafe) static var provider: (() -> [ContextNote])?
    static func live() -> [ContextNote] { provider?() ?? [] }
}
