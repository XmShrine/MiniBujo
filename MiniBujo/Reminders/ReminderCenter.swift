import Foundation
import Observation
import UserNotifications

/// 把 ReminderPlanner 算出来的提醒交给系统；点通知时跳到对应页面
@MainActor
@Observable
final class ReminderCenter: NSObject {
    var prefs: ReminderPrefs { didSet { save(); schedule() } }
    private(set) var authorized: Bool?
    private(set) var pendingCount = 0

    @ObservationIgnored private weak var store: BujoStore?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    private static let key = "reminderPrefs"

    override init() {
        prefs = (UserDefaults.standard.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode(ReminderPrefs.self, from: $0) } ?? ReminderPrefs()
        super.init()
        center.delegate = self
    }

    func attach(_ store: BujoStore) { self.store = store }

    private func save() {
        if let d = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func refreshAuthorization() async {
        let s = await center.notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            ? true : s.authorizationStatus == .notDetermined ? nil : false
    }

    /// 第一次启动时问一次权限
    func requestIfNeeded() async {
        await refreshAuthorization()
        guard prefs.enabled, authorized == nil else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
        schedule()
    }

    /// 手帐有改动时调用，去抖 1.5 秒后重排
    func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { await self?.rescheduleNow() }
        }
    }

    func rescheduleNow() async {
        guard let store else { return }
        let plan = ReminderPlanner.plan(doc: store.doc, prefs: prefs, now: Date())
        center.removeAllPendingNotificationRequests()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { pendingCount = 0; return }
        for r in plan {
            let c = UNMutableNotificationContent()
            c.title = r.title
            c.body = r.body
            c.sound = .default
            c.threadIdentifier = r.day
            c.userInfo = ["view": r.view, "day": r.day]
            let comps = Dates.cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.fire)
            let req = UNNotificationRequest(identifier: r.id, content: c,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
        pendingCount = plan.count
    }

    func sendTest() {
        let c = UNMutableNotificationContent()
        c.title = "提醒已开启"
        c.body = "到时候会像这样提醒你 ✏️"
        c.sound = .default
        center.add(UNNotificationRequest(identifier: "bujo.test", content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
    }
}

extension ReminderCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let v = info["view"] as? String, let d = info["day"] as? String, let tab = Tab(rawValue: v) else { return }
        await MainActor.run { self.store?.go(tab, d) }
    }
}
