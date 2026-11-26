import SwiftUI
#if os(iOS)
import BackgroundTasks
#endif

@main
struct MiniBujoApp: App {
    @State private var store: BujoStore
    @State private var sync: FileSync
    @State private var reminders: ReminderCenter
    @Environment(\.scenePhase) private var phase

    #if os(macOS)
    @StateObject private var appUpdater = AppUpdater()
    #endif

    static let refreshTaskID = "com.xmshrine.minibujo.refresh"

    init() {
        let sync = FileSync()
        let store = BujoStore(doc: sync.loadLocal())
        let reminders = ReminderCenter()
        store.onChange = { [weak sync, weak reminders] in
            sync?.scheduleSave()
            reminders?.schedule()
        }
        store.onReplace = { [weak reminders] in reminders?.schedule() }
        sync.attach(store)
        reminders.attach(store)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        _reminders = State(initialValue: reminders)
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sync.flush() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                .environment(reminders)
                .task {
                    #if os(macOS)
                    appUpdater.start(beforeRelaunch: { sync.flush() })
                    #endif
                    await reminders.requestIfNeeded()
                    reminders.schedule()
                }
                .onChange(of: phase) { _, p in
                    switch p {
                    case .active:
                        store.rollDateIfNeeded()
                        sync.pullIfNewer()
                        Task { await reminders.refreshAuthorization(); reminders.schedule() }
                    case .background:
                        sync.flush()
                        Task { await reminders.rescheduleNow() }
                        #if os(iOS)
                        Self.scheduleAppRefresh()
                        #endif
                    default: break
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 900)
        #endif
        .commands {
            BujoCommands(store: store)
            #if os(macOS)
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { appUpdater.checkForUpdates() }
                    .disabled(!appUpdater.canCheckForUpdates)
                Button("安装 / 更新到 iPhone…") {
                    NotificationCenter.default.post(name: .openIOSInstaller, object: nil)
                }
            }
            #endif
        }
        #if os(iOS)
        // 后台刷新：别的设备改了 iCloud 里的文件，这台设备也能及时重排提醒
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await MainActor.run { Self.scheduleAppRefresh() }
            await sync.pullAndWait()
            await reminders.rescheduleNow()
        }
        #endif
    }

    #if os(iOS)
    static func scheduleAppRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date().addingTimeInterval(3 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
    #endif
}

#if os(macOS)
extension Notification.Name {
    static let openIOSInstaller = Notification.Name("com.xmshrine.minibujo.openIOSInstaller")
}
#endif

/// 键盘快捷键（Mac 和接了键盘的 iPad）
struct BujoCommands: Commands {
    let store: BujoStore

    var body: some Commands {
        CommandMenu("翻页") {
            Button("上一页") { store.nav(-1) }.keyboardShortcut("[", modifiers: .command)
            Button("下一页") { store.nav(1) }.keyboardShortcut("]", modifiers: .command)
            Button("今天") { store.nav(0) }.keyboardShortcut("t", modifiers: .command)
            Divider()
            ForEach(Array(Tab.allCases.enumerated()), id: \.1) { i, t in
                Button("\(t.cn) · \(t.en)") { store.go(t) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
    }
}
