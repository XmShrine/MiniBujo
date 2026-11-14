import Foundation

/// 每台设备各自的提醒设置（存在本机，不进 iCloud 文件：比如只想让 iPhone 响，Mac 不响）
struct ReminderPrefs: Codable, Equatable {
    var enabled = true
    /// 红点 / 蓝点日：红点前一晚 + 当天早上，蓝点当天早上
    var dotDays = true
    var eveMin = 21 * 60
    var morningMin = 8 * 60
    /// 日视图时间轴里写了内容的整点
    var timeline = true
    /// 月记、任务、事件里写的「15:30」这类时间
    var textTimes = true
    var leadMin = 10
    /// 晚上提醒打卡、记心情、迁移未完成任务
    var checkin = true
    var checkinMin = 21 * 60 + 30
    /// 周日晚上的周小结
    var weekly = true
    var weeklyMin = 20 * 60

    init() {}
    enum CodingKeys: String, CodingKey {
        case enabled, dotDays, eveMin, morningMin, timeline, textTimes, leadMin, checkin, checkinMin, weekly, weeklyMin
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = ReminderPrefs()
        enabled = c.v(.enabled, d.enabled); dotDays = c.v(.dotDays, d.dotDays)
        eveMin = c.v(.eveMin, d.eveMin); morningMin = c.v(.morningMin, d.morningMin)
        timeline = c.v(.timeline, d.timeline); textTimes = c.v(.textTimes, d.textTimes); leadMin = c.v(.leadMin, d.leadMin)
        checkin = c.v(.checkin, d.checkin); checkinMin = c.v(.checkinMin, d.checkinMin)
        weekly = c.v(.weekly, d.weekly); weeklyMin = c.v(.weeklyMin, d.weeklyMin)
    }
}

struct PlannedReminder: Equatable {
    let id: String
    let fire: Date
    let title: String
    let body: String
    /// 点通知后打开的页面
    let view: String
    let day: String
}

/// 根据手帐内容算出接下来要发的本地通知。纯函数，方便测试。
enum ReminderPlanner {
    static let horizonDays = 14
    /// iOS 最多 64 条待发通知，留一点余量
    static let maxCount = 60

    static func at(_ s: String, minutes: Int) -> Date {
        Dates.cal.date(byAdding: .minute, value: minutes, to: Dates.pd(s))!
    }

    /// 找出文字里的 9:30 / 21：05 这类时间
    private static let timeRE = try! NSRegularExpression(pattern: "(?<![\\d:：.])([01]?\\d|2[0-3])[:：]([0-5]\\d)(?![\\d:：])")
    static func times(in text: String) -> [Int] {
        let ns = text as NSString
        return timeRE.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            Int(ns.substring(with: $0.range(at: 1)))! * 60 + Int(ns.substring(with: $0.range(at: 2)))!
        }
    }

    static func summary(_ o: Day?) -> String {
        guard let o else { return "打开看看这天的安排" }
        let log = o.mlog.trimmingCharacters(in: .whitespacesAndNewlines)
        if !log.isEmpty { return log }
        let tasks = (o.main + o.light).filter { !$0.isClosed && !$0.x.isEmpty }.prefix(3).map(\.x)
        return tasks.isEmpty ? "打开看看这天的安排" : tasks.joined(separator: "、")
    }

    static func plan(doc: Doc, prefs: ReminderPrefs, now: Date) -> [PlannedReminder] {
        guard prefs.enabled else { return [] }
        let today = Dates.ds(now)
        var out: [PlannedReminder] = []
        func add(_ id: String, _ fire: Date, _ title: String, _ body: String, _ view: String, _ day: String) {
            if fire > now { out.append(.init(id: "bujo.\(id)", fire: fire, title: title, body: body, view: view, day: day)) }
        }

        for k in 0..<horizonDays {
            let s = Dates.addDays(today, k), o = doc.days[s]

            if prefs.dotDays, let dot = o?.dot {
                let sum = summary(o)
                if dot == "red" {
                    add("eve.\(s)", at(Dates.addDays(s, -1), minutes: prefs.eveMin), "🔴 明天有重要安排", sum, "day", s)
                    add("morning.\(s)", at(s, minutes: prefs.morningMin), "🔴 今天有重要安排", sum, "day", s)
                } else if dot == "blue" {
                    add("morning.\(s)", at(s, minutes: prefs.morningMin), "🔵 今天有预约", sum, "day", s)
                }
            }

            if prefs.timeline, let o {
                for (hk, text) in o.times.sorted(by: { $0.key < $1.key }) {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty, let h = Int(hk) else { continue }
                    let lead = prefs.leadMin > 0 ? "\(prefs.leadMin) 分钟后 · " : ""
                    add("tl.\(s).\(hk)", at(s, minutes: h * 60 - prefs.leadMin), "\(h):00 \(t)", "\(lead)\(Dates.fmtMD(s)) 时间轴", "day", s)
                }
            }

            if prefs.textTimes, let o {
                var lines: [(String, String)] = o.mlog.split(whereSeparator: \.isNewline).map { ("log", String($0)) }
                for it in o.main + o.light where it.t != "note" && !it.isClosed { lines.append((it.id, it.x)) }
                for (n, (key, line)) in lines.enumerated() {
                    for m in times(in: line) {
                        let hm = "\(m / 60):\(Dates.pad(m % 60))"
                        add("tx.\(s).\(key).\(n).\(m)", at(s, minutes: m - prefs.leadMin),
                            line.trimmingCharacters(in: .whitespaces), "\(Dates.fmtMD(s)) \(hm)", "day", s)
                    }
                }
            }

            if prefs.checkin, k < 7 {
                let mon = Dates.mondayOf(s), i = Dates.wdIdx(s)
                let habits = doc.weeks[mon]?.habits ?? []
                let unmarked = habits.filter { $0.marks[i].isEmpty && !$0.name.isEmpty }.map(\.name)
                let open = (o?.main ?? []).filter(\.isOpenTask).count + (o?.light ?? []).filter(\.isOpenTask).count
                let noMood = o?.mood == nil
                var parts: [String] = []
                if !unmarked.isEmpty && doc.weeks[mon] != nil {
                    parts.append("还没打卡：" + unmarked.prefix(4).joined(separator: "、") + (unmarked.count > 4 ? "…" : ""))
                }
                if noMood { parts.append("心情还没记") }
                if open > 0 { parts.append("还有 \(open) 项没做完，可以迁移到明天") }
                let allDone = s == today && parts.isEmpty
                if !allDone {
                    add("checkin.\(s)", at(s, minutes: prefs.checkinMin), "今天过得怎么样？",
                        parts.isEmpty ? "记一下心情、打个卡吧" : parts.joined(separator: " · "), k == 0 ? "day" : "habits", s)
                }
            }

            if prefs.weekly, k < 7, Dates.wdIdx(s) == 6 {
                let mon = Dates.mondayOf(s)
                let w = doc.weeks[mon]
                let open = ((w?.serious ?? []) + (w?.light ?? [])).filter(\.isOpenTask).count
                let body = open > 0 ? "这周还有 \(open) 项没完成，可以「未完成 → 下周」· 顺便写写本周小结"
                                    : "写写本周小结，看看下周要做什么"
                add("weekly.\(mon)", at(s, minutes: prefs.weeklyMin), "周日小结 · week \(Dates.weekNo(mon))", body, "week", s)
            }
        }
        return Array(out.sorted { $0.fire < $1.fire }.prefix(maxCount))
    }
}
