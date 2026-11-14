import Foundation
import Observation

enum Tab: String, CaseIterable, Identifiable {
    case month, week, day, habits, cols, pixels, index
    var id: String { rawValue }
    var cn: String { ["月", "周", "日", "打卡", "跟踪", "心情", "索引"][Tab.allCases.firstIndex(of: self)!] }
    var en: String { ["month", "week", "day", "habits", "collections", "pixels", "index"][Tab.allCases.firstIndex(of: self)!] }
}

/// 列表引用，对应网页版的 day|日期|main 这类字符串
enum ListRef: Hashable {
    case day(String, String)    // 日期, main / light
    case wk(String, String)     // 周一, serious / light / track
    case wl(String, String)     // 周一, 清单 id
    case col(String)
    case mg(String)             // 年-月

    var migrateTarget: (ref: ListRef, label: String)? {
        switch self {
        case let .day(d, b): return (.day(Dates.addDays(d, 1), b), "明天")
        case let .wk(m, b): return (.wk(Dates.addDays(m, 7), b), "下周")
        default: return nil
        }
    }
}

struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    var message: String = ""
    var button: String = "删除"
    let action: () -> Void
}

struct SearchHit: Identifiable {
    let id = UUID()
    enum Target { case day(String), week(String), habits(String), col(String) }
    let target: Target
    let where_: String
    let text: String
}

@MainActor
@Observable
final class BujoStore {
    var doc: Doc
    var view: Tab { didSet { defaults.set(view.rawValue, forKey: "view") } }
    var date: String = Dates.today()
    var colID: String? { didSet { defaults.set(colID, forKey: "col") } }
    var query: String { didSet { defaults.set(query, forKey: "q") } }
    var hideBanner: Bool { didSet { defaults.set(hideBanner, forKey: "hideBanner") } }

    var toast: String?
    var confirm: ConfirmRequest?
    /// 每次修改都 +1，外部（存文件、排提醒）据此去抖
    var revision = 0

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var weekTpl: [String: Week] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onReplace: (() -> Void)?
    @ObservationIgnored private var lastToday = Dates.today()

    init(doc: Doc = Doc()) {
        self.doc = doc
        view = Tab(rawValue: defaults.string(forKey: "view") ?? "") ?? .week
        colID = defaults.string(forKey: "col")
        query = defaults.string(forKey: "q") ?? ""
        hideBanner = defaults.bool(forKey: "hideBanner")
    }

    // MARK: - change tracking

    func mutate(_ f: (inout Doc) -> Void) {
        f(&doc)
        doc.updatedAt = (Date().timeIntervalSince1970 * 1000).rounded()
        revision += 1
        onChange?()
    }

    /// 从文件载入：不改 updatedAt
    func replace(with d: Doc) {
        doc = d
        weekTpl = [:]
        revision += 1
        onReplace?()
    }

    /// App 开着过了零点：原本停在「今天」的话跟着翻到新的今天
    func rollDateIfNeeded() {
        let t = Dates.today()
        if t != lastToday {
            if date == lastToday { date = t }
            lastToday = t
        }
    }

    func showToast(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: - navigation

    func go(_ tab: Tab, _ d: String? = nil) {
        view = tab
        if let d { date = d }
    }

    func nav(_ dir: Int) {
        if dir == 0 { date = Dates.today(); return }
        switch view {
        case .month: date = Dates.addMonths(date, dir)
        case .week, .habits: date = Dates.addDays(date, 7 * dir)
        case .pixels: date = "\(Dates.year(date) + dir)-01-01"
        default: date = Dates.addDays(date, dir)
        }
    }

    var navLabel: String? {
        let mon = Dates.mondayOf(date)
        switch view {
        case .month: return "\(Dates.MONTHS[Dates.month(date) - 1]) \(Dates.year(date))"
        case .week, .habits: return "week \(Dates.weekNo(mon)) · \(Dates.fmtMD(mon))–\(Dates.fmtMD(Dates.addDays(mon, 6)))"
        case .day: return "\(Dates.fmtMD(date)) 周\(Dates.WD_CN[Dates.wdIdx(date)])"
        case .pixels: return String(date.prefix(4))
        default: return nil
        }
    }

    // MARK: - weeks（只是翻看时不写入；第一次编辑才落盘）

    func peekWeek(_ mon: String) -> Week {
        if let w = doc.weeks[mon] { return w }
        if let t = weekTpl[mon] { return t }
        let t = doc.newWeek(mon)
        weekTpl[mon] = t
        return t
    }

    func editWeek(_ mon: String, _ f: (inout Week) -> Void) {
        let tpl = weekTpl.removeValue(forKey: mon)
        mutate { d in
            if d.weeks[mon] == nil { d.weeks[mon] = tpl ?? d.newWeek(mon) }
            f(&d.weeks[mon]!)
        }
    }

    func editDay(_ s: String, _ f: (inout Day) -> Void) {
        mutate { f(&$0.days[s, default: Day()]) }
    }

    // MARK: - lists

    func items(_ ref: ListRef) -> [Item] {
        switch ref {
        case let .day(d, b): let o = doc.days[d]; return (b == "main" ? o?.main : o?.light) ?? []
        case let .wk(m, b):
            let w = peekWeek(m)
            return b == "serious" ? w.serious : b == "light" ? w.light : w.track
        case let .wl(m, id): return peekWeek(m).lists.first { $0.id == id }?.items ?? []
        case let .col(id): return doc.cols.first { $0.id == id }?.items ?? []
        case let .mg(k): return doc.months[k]?.goals ?? []
        }
    }

    func editList(_ ref: ListRef, _ f: (inout [Item]) -> Void) {
        switch ref {
        case let .day(d, b):
            editDay(d) { b == "main" ? f(&$0.main) : f(&$0.light) }
        case let .wk(m, b):
            editWeek(m) { w in
                switch b {
                case "serious": f(&w.serious)
                case "light": f(&w.light)
                default: f(&w.track)
                }
            }
        case let .wl(m, id):
            editWeek(m) { w in if let i = w.lists.firstIndex(where: { $0.id == id }) { f(&w.lists[i].items) } }
        case let .col(id):
            mutate { d in if let i = d.cols.firstIndex(where: { $0.id == id }) { f(&d.cols[i].items) } }
        case let .mg(k):
            mutate { f(&$0.months[k, default: Month()].goals) }
        }
    }

    func editItem(_ ref: ListRef, _ id: String, _ f: (inout Item) -> Void) {
        editList(ref) { arr in if let i = arr.firstIndex(where: { $0.id == id }) { f(&arr[i]) } }
    }

    func addItem(_ ref: ListRef, _ raw: String) {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        editList(ref) { $0.append(Item.parseNew(v)) }
    }

    func deleteItem(_ ref: ListRef, _ id: String) {
        editList(ref) { $0.removeAll { $0.id == id } }
    }

    func moveItem(_ ref: ListRef, _ id: String, to slot: String) {
        guard let it = items(ref).first(where: { $0.id == id }) else { return }
        let dest: ListRef
        switch ref {
        case let .day(d, _): dest = .day(d, slot)
        case let .wk(m, _): dest = .wk(m, slot)
        default: return
        }
        deleteItem(ref, id)
        editList(dest) { $0.append(it) }
    }

    func migrate(_ ref: ListRef, _ id: String) {
        guard let tg = ref.migrateTarget, let it = items(ref).first(where: { $0.id == id }) else { return }
        var copy = it
        copy.id = uid(); copy.s = "open"; copy.st = false
        editList(tg.ref) { $0.append(copy) }
        editItem(ref, id) { $0.s = "migrated" }
        showToast("已迁移到\(tg.label)")
    }

    func migrateAll(_ refs: [ListRef]) {
        var n = 0
        for ref in refs {
            for it in items(ref) where it.isOpenTask {
                guard let tg = ref.migrateTarget else { continue }
                var copy = it
                copy.id = uid(); copy.s = "open"; copy.st = false
                editList(tg.ref) { $0.append(copy) }
                editItem(ref, it.id) { $0.s = "migrated" }
                n += 1
            }
        }
        showToast(n > 0 ? "已迁移 \(n) 项未完成任务" : "没有需要迁移的任务")
    }

    // MARK: - stickers

    func cycleDot(_ s: String) {
        editDay(s) { $0.dot = $0.dot == "red" ? "blue" : $0.dot == "blue" ? nil : "red" }
    }

    func setMood(_ s: String, _ m: Mood?) {
        editDay(s) { $0.mood = m?.rawValue }
    }

    // MARK: - search

    func search(_ raw: String) -> [SearchHit] {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        func hit(_ s: String?) -> Bool { (s ?? "").lowercased().contains(q) }
        var R: [SearchHit] = []
        for (d, o) in doc.days.sorted(by: { $0.key > $1.key }) {
            for it in o.main + o.light where hit(it.x) { R.append(.init(target: .day(d), where_: d, text: it.x)) }
            if hit(o.mlog) { R.append(.init(target: .day(d), where_: d + " 月记", text: o.mlog)) }
            if hit(o.note) { R.append(.init(target: .day(d), where_: d + " 随手记", text: o.note)) }
            for c in o.cards where hit(c.title) || hit(c.body) {
                R.append(.init(target: .day(d), where_: d + " 卡片", text: hit(c.title) ? c.title : c.body))
            }
            for (_, v) in o.times.sorted(by: { $0.key < $1.key }) where hit(v) {
                R.append(.init(target: .day(d), where_: d + " 时间轴", text: v))
            }
        }
        for (mon, w) in doc.weeks.sorted(by: { $0.key > $1.key }) {
            let wh = "week \(Dates.weekNo(mon)) · \(mon.prefix(4))"
            for it in w.serious + w.light + w.track where hit(it.x) { R.append(.init(target: .week(mon), where_: wh, text: it.x)) }
            for l in w.lists { for it in l.items where hit(it.x) { R.append(.init(target: .habits(mon), where_: "\(wh) \(l.title)", text: it.x)) } }
            if hit(w.thoughts) { R.append(.init(target: .habits(mon), where_: wh, text: w.thoughts)) }
        }
        for c in doc.cols { for it in c.items where hit(it.x) { R.append(.init(target: .col(c.id), where_: c.title.isEmpty ? "跟踪页" : c.title, text: it.x)) } }
        return Array(R.prefix(120))
    }

    func open(_ t: SearchHit.Target) {
        switch t {
        case let .day(d): go(.day, d)
        case let .week(m): go(.week, m)
        case let .habits(m): go(.habits, m)
        case let .col(id): colID = id; go(.cols)
        }
    }
}
