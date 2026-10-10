import Foundation
import Combine

/// 用户授权文件夹中的历史记录同步，不需要 iCloud 容器或个人签名配置。
enum CloudSyncState: Equatable {
    case idle, syncing, success
    case error(String)
}

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    private let bookmarkKey = "icloud_drive_folder_bookmark_v2"
    private let folderNameKey = "icloud_drive_folder_name_v2"
    private let lastSyncKey = "icloud_drive_last_sync_time_v2"
    private var pendingSync = false
    private var bindingGeneration = 0

    @Published private(set) var bindingError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var syncState: CloudSyncState = .idle
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var statusMessage = "未绑定 iCloud 云盘文件夹"
    @Published private(set) var isFolderBound = false
    @Published private(set) var boundFolderName = ""

    init() {
        isFolderBound = UserDefaults.standard.data(forKey: bookmarkKey) != nil
        boundFolderName = UserDefaults.standard.string(forKey: folderNameKey) ?? ""
        lastSyncTime = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        if isFolderBound { statusMessage = "已绑定「\(boundFolderName)」" }
    }

    func bindFolder(url: URL, historyStore: HistoryStore) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try SyncFolderAccess.validate(url)
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            bindingError = nil
            bindingGeneration += 1
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
            boundFolderName = url.lastPathComponent
            isFolderBound = true
            syncNow(historyStore: historyStore)
        } catch {
            bindingError = error.localizedDescription
            // 更换目录失败时保留已绑定目录和原同步状态。
            if !isFolderBound { statusMessage = "绑定失败：\(error.localizedDescription)" }
        }
    }

    func clearBindingError() { bindingError = nil }

    func unbindFolder() {
        bindingError = nil
        bindingGeneration += 1
        pendingSync = false
        for key in [bookmarkKey, folderNameKey, lastSyncKey] { UserDefaults.standard.removeObject(forKey: key) }
        isFolderBound = false
        boundFolderName = ""
        lastSyncTime = nil
        syncState = .idle
        statusMessage = "未绑定 iCloud 云盘文件夹"
    }

    func syncNow(historyStore: HistoryStore) {
        guard isFolderBound, let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        guard !isSyncing else { pendingSync = true; return }
        isSyncing = true
        syncState = .syncing
        statusMessage = "正在同步 iCloud 云盘..."
        let records = historyStore.records
        let generation = bindingGeneration
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try Self.mergeFile(bookmark: bookmark, localRecords: records)
                }.value
                if generation == bindingGeneration {
                    historyStore.merge(cloudRecords: result.records)
                    UserDefaults.standard.set(result.bookmark, forKey: bookmarkKey)
                    let now = Date()
                    lastSyncTime = now
                    UserDefaults.standard.set(now, forKey: lastSyncKey)
                    syncState = .success
                    statusMessage = "同步成功（\(historyStore.records.count) 条记录）"
                }
            } catch {
                if generation == bindingGeneration {
                    syncState = .error(error.localizedDescription)
                    statusMessage = "同步失败：\(error.localizedDescription)"
                }
            }
            isSyncing = false
            if pendingSync {
                pendingSync = false
                syncNow(historyStore: historyStore)
            }
        }
    }

    func uploadToCloud(records: [Measurement]) {
        // 测量完成也执行双向合并，避免覆盖其他设备的记录。
        syncNow(historyStore: HistoryStore.shared)
    }

    private nonisolated static func mergeFile(bookmark: Data, localRecords: [Measurement]) throws
        -> (records: [Measurement], bookmark: Data) {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        try SyncFolderAccess.validate(folder)
        guard accessing || SyncFolderAccess.isAppLocalDirectory(folder) else { throw CocoaError(.fileReadNoPermission) }
        let renewed = stale ? try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : bookmark
        let file = folder.appendingPathComponent("measurements_history.json")
        var coordinationError: NSError?
        var operationResult: Result<[Measurement], Error>?
        // 在同一协调写入事务内读取、合并、原子写回；任何读取/解码错误都停止写入。
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forMerging, error: &coordinationError) { coordinatedURL in
            operationResult = Result {
                let remote: [Measurement]
                do {
                    let values = try coordinatedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
                    guard values.isSymbolicLink != true else { throw SyncFolderAccess.ValidationError.unsupportedProvider }
                    remote = try JSONDecoder().decode([Measurement].self, from: Data(contentsOf: coordinatedURL))
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    remote = []
                }
                var byID: [UUID: Measurement] = [:]
                for record in remote + localRecords { byID[record.id] = record }
                let merged = byID.values.sorted { $0.date > $1.date }
                try JSONEncoder().encode(merged).write(to: coordinatedURL, options: .atomic)
                return merged
            }
        }
        if let coordinationError { throw coordinationError }
        guard let operationResult else { throw CocoaError(.fileWriteUnknown) }
        return (try operationResult.get(), renewed)
    }
}
