import Foundation
import Observation

/* 存储：
   1. 本机缓存（Application Support/MiniBujo/my-bujo.json），相当于网页版的 localStorage，随时可用。
   2. 关联的 iCloud 云盘文件夹里的 my-bujo.json。用户选一次文件夹，App 记住授权（安全书签），
      之后每次修改都自动写进去；iCloud 负责在 iPhone / iPad / Mac 之间同步。
      免费开发者账号不能开 App 专属的 iCloud 容器，所以走「用户选文件夹」这条路，网页版也能打开同一个文件。
   冲突处理和网页版一致：比较 updatedAt，新的覆盖旧的。 */

@MainActor
@Observable
final class FileSync {
    enum Phase: Equatable { case idle, saving, saved(Date), error(String) }

    static let fileName = "my-bujo.json"

    private(set) var folderName: String?
    private(set) var phase: Phase = .idle
    private(set) var needsRelink = false

    var isLinked: Bool { folderURL != nil }
    var fileURL: URL? { folderURL?.appendingPathComponent(FileSync.fileName) }

    @ObservationIgnored private weak var store: BujoStore?
    @ObservationIgnored private var folderURL: URL?
    @ObservationIgnored private var presenter: FilePresenter?
    @ObservationIgnored private let io = DispatchQueue(label: "minibujo.io", qos: .utility)
    @ObservationIgnored private var localTask: Task<Void, Never>?
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    @ObservationIgnored private var fileDirty = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let bookmarkKey = "linkedFolderBookmark"

    let localURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniBujo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(FileSync.fileName)
    }()

    /// 启动时同步读本机缓存，保证界面一出来就有内容。
    /// macOS 1.4 起关闭 App Sandbox（以支持内置 iPhone 一键安装），
    /// 首次启动时自动从旧沙盒容器迁移未关联 iCloud 的本机数据与偏好。
    func loadLocal() -> Doc {
        #if os(macOS)
        migrateFromLegacySandboxIfNeeded()
        #endif
        return (try? Data(contentsOf: localURL)).flatMap(Doc.parse) ?? Doc()
    }

    #if os(macOS)
    private func migrateFromLegacySandboxIfNeeded() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var bundleIDs = ["com.xmshrine.minibujo", "com.xmshrine.minibujo.v12"]
        if let cur = Bundle.main.bundleIdentifier, !bundleIDs.contains(cur) { bundleIDs.insert(cur, at: 0) }

        // 1. 迁移本机 my-bujo.json（仅当非沙盒目录尚无文件时）
        if !fm.fileExists(atPath: localURL.path) {
            var bestData: Data?
            var bestUpdatedAt: Double = -1
            for bid in bundleIDs {
                let legacy = home
                    .appendingPathComponent("Library/Containers/\(bid)/Data/Library/Application Support/MiniBujo/\(Self.fileName)")
                if let data = try? Data(contentsOf: legacy), let doc = Doc.parse(data), doc.updatedAt > bestUpdatedAt {
                    bestData = data
                    bestUpdatedAt = doc.updatedAt
                }
            }
            if let bestData { try? bestData.write(to: localURL, options: .atomic) }
        }

        // 2. 迁移常用偏好设置（仅执行一次，且不覆盖已有新值）
        let flagKey = "migratedFromLegacySandboxV1"
        guard !defaults.bool(forKey: flagKey) else { return }
        defaults.set(true, forKey: flagKey)
        let keysToMigrate = [
            Self.bookmarkKey, "view", "hideBanner",
            AppearanceKeys.paperForm, AppearanceKeys.font, AppearanceKeys.textSize, AppearanceKeys.palette
        ]
        for bid in bundleIDs {
            let plist = home.appendingPathComponent("Library/Containers/\(bid)/Data/Library/Preferences/\(bid).plist")
            guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { continue }
            for key in keysToMigrate where defaults.object(forKey: key) == nil {
                if let v = dict[key] { defaults.set(v, forKey: key) }
            }
        }
    }
    #endif

    func attach(_ store: BujoStore) {
        self.store = store
        if let data = defaults.data(forKey: Self.bookmarkKey) { restore(bookmark: data) }
    }

    // MARK: - linking

    func link(folder url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            #if os(macOS)
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            defaults.set(data, forKey: Self.bookmarkKey)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            phase = .error("没法记住这个文件夹：\(error.localizedDescription)")
            return
        }
        unlinkCurrent()
        use(folder: url)
        reconcile(announce: true)
    }

    func unlink() {
        unlinkCurrent()
        defaults.removeObject(forKey: Self.bookmarkKey)
        phase = .idle
        needsRelink = false
    }

    private func unlinkCurrent() {
        if let p = presenter { NSFileCoordinator.removeFilePresenter(p) }
        presenter = nil
        folderURL?.stopAccessingSecurityScopedResource()
        folderURL = nil
        folderName = nil
    }

    private func restore(bookmark data: Data) {
        var stale = false
        do {
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            _ = url.startAccessingSecurityScopedResource()
            guard FileManager.default.fileExists(atPath: url.path) else { needsRelink = true; return }
            if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Self.bookmarkKey)
            }
            #else
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else { needsRelink = true; return }
            if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Self.bookmarkKey)
            }
            #endif
            use(folder: url)
            reconcile(announce: false)
        } catch {
            needsRelink = true
        }
    }

    private func use(folder url: URL) {
        folderURL = url
        folderName = url.lastPathComponent
        needsRelink = false
        let p = FilePresenter(url: url.appendingPathComponent(Self.fileName)) { [weak self] in
            Task { @MainActor in self?.pullIfNewer() }
        }
        NSFileCoordinator.addFilePresenter(p)
        presenter = p
    }

    // MARK: - saving

    /// 每次修改后调用：本机缓存 0.3 秒后写，iCloud 文件 1 秒后写
    func scheduleSave() {
        localTask?.cancel()
        localTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { self?.writeLocal() }
        }
        guard isLinked else { return }
        fileDirty = true
        phase = .saving
        fileTask?.cancel()
        fileTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { self?.writeFile() }
        }
    }

    /// 切到后台 / 退出前：立刻写完
    func flush() {
        localTask?.cancel(); fileTask?.cancel()
        guard let store else { return }
        let data = store.doc.serialized()
        let local = localURL
        io.sync { try? data.write(to: local, options: .atomic) }
        if isLinked && fileDirty, let url = fileURL {
            let ok = io.sync { Self.coordinatedWrite(data, to: url, presenter: presenter) }
            finishWrite(ok: ok)
        }
    }

    private func writeLocal() {
        guard let store else { return }
        let data = store.doc.serialized(), url = localURL
        io.async { try? data.write(to: url, options: .atomic) }
    }

    private func writeFile() {
        guard let store, let url = fileURL else { return }
        let data = store.doc.serialized(), p = presenter
        io.async {
            let ok = Self.coordinatedWrite(data, to: url, presenter: p)
            Task { @MainActor [weak self] in self?.finishWrite(ok: ok) }
        }
    }

    private func finishWrite(ok: Bool) {
        if ok { fileDirty = false; phase = .saved(Date()) }
        else { phase = .error("写入 iCloud 文件失败，稍后会重试") }
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL, presenter: NSFilePresenter?) -> Bool {
        var ok = false, err: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            ok = (try? data.write(to: u, options: .atomic)) != nil
        }
        return ok && err == nil
    }

    // MARK: - reading

    /// 回到前台、别的设备改了文件时调用：文件比手上的新就载入
    func pullIfNewer() {
        guard isLinked else { return }
        reconcile(announce: true)
    }

    /// 和网页版 reconnect() 同样的规则：文件新 → 载入；手上新 → 写回文件；一样 → 不动
    private func reconcile(announce: Bool, done: (() -> Void)? = nil) {
        guard let url = fileURL else { done?(); return }
        let p = presenter
        io.async {
            let r = Self.readBest(url, presenter: p)
            Task { @MainActor [weak self] in
                self?.apply(r, announce: announce)
                done?()
            }
        }
    }

    /// 后台刷新用：等读完再返回
    func pullAndWait() async {
        guard isLinked else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            reconcile(announce: false) { c.resume() }
        }
    }

    private func apply(_ r: ReadResult, announce: Bool) {
        guard let store else { return }
        switch r {
        case let .doc(remote, fromConflict):
            if remote.updatedAt > store.doc.updatedAt {
                store.replace(with: remote)
                writeLocal()
                phase = .saved(Date())
                if announce { store.showToast("已从 iCloud 同步最新内容") }
                if fromConflict { fileDirty = true; writeFile() }
            } else if remote.updatedAt < store.doc.updatedAt || fromConflict {
                fileDirty = true; phase = .saving; writeFile()
            } else {
                fileDirty = false
                if case .saving = phase {} else { phase = .saved(Date()) }
            }
        case .missing:
            fileDirty = true; phase = .saving; writeFile()
        case .unreadable:
            phase = .error("文件夹里的 \(Self.fileName) 不是 mini bujo 的数据，没有覆盖它")
        case .notReady:
            phase = .error("iCloud 文件还在下载，稍后自动重试")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.pullIfNewer()
            }
        }
    }

    enum ReadResult { case doc(Doc, fromConflict: Bool), missing, unreadable, notReady }

    nonisolated private static func readBest(_ url: URL, presenter: NSFilePresenter?) -> ReadResult {
        let fm = FileManager.default
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        let exists = fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholder.path)
        guard exists else { return .missing }
        try? fm.startDownloadingUbiquitousItem(at: url)

        var data: Data?, err: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: [], error: &err) { u in
            data = try? Data(contentsOf: u)
        }
        guard let data else { return .notReady }
        guard var best = Doc.parse(data) else { return .unreadable }

        // iCloud 冲突版本：挑 updatedAt 最新的那份，其余标记为已解决
        var fromConflict = false
        if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflicts.isEmpty {
            for v in conflicts {
                if let d = (try? Data(contentsOf: v.url)).flatMap(Doc.parse), d.updatedAt > best.updatedAt {
                    best = d; fromConflict = true
                }
                v.isResolved = true
            }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return .doc(best, fromConflict: fromConflict)
    }

    // MARK: - import / export

    func importDoc(from url: URL) -> Doc? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var data: Data?, err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        return data.flatMap(Doc.parse)
    }

    var statusText: (text: String, warn: Bool) {
        if needsRelink { return ("iCloud 文件夹授权失效，请重新关联", true) }
        guard isLinked else {
            return (store?.doc.updatedAt ?? 0 > 0 ? "未关联 iCloud 文件夹 · 暂存在本机" : "暂存在本机", store?.doc.updatedAt ?? 0 > 0)
        }
        let name = "☁︎ \(folderName ?? "")/\(Self.fileName)"
        switch phase {
        case .idle: return (name, false)
        case .saving: return ("\(name) · 保存中…", false)
        case let .saved(d): return ("\(name) · 已保存 \(Dates.hhmm(d))", false)
        case let .error(m): return ("\(name) · \(m)", true)
        }
    }
}

/// 监听 iCloud 文件被别的设备改动
final class FilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    func presentedItemDidChange() { onChange() }
    func presentedItemDidGain(_ version: NSFileVersion) { onChange() }
    func presentedItemDidResolveConflict(_ version: NSFileVersion) { onChange() }
}
