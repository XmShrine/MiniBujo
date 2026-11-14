import Foundation

/* 数据结构和网页版完全一致：一个 JSON 对象，网页导出的 .json 可以直接导入，反过来也一样。
   解码时宽松处理（缺字段、类型不对都用默认值），编码时字段齐全，保证网页版读得懂。 */

extension KeyedDecodingContainer {
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

func uid() -> String {
    let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return String((0..<7).map { _ in chars.randomElement()! })
}

enum Mood: String, CaseIterable, Codable { case red, orange, yellow, green, blue }
enum Dot: String, Codable { case red, blue }

/// 子弹条目：t = task / event / note，s = open / started / done / cancelled / migrated
struct Item: Codable, Identifiable, Equatable {
    var id: String = uid()
    var t: String = "task"
    var s: String? = "open"
    var x: String = ""
    var p: Bool? = nil
    var st: Bool? = nil

    init(id: String = uid(), t: String = "task", s: String? = "open", x: String = "", p: Bool? = nil, st: Bool? = nil) {
        self.id = id; self.t = t; self.s = s; self.x = x; self.p = p; self.st = st
    }

    enum CodingKeys: String, CodingKey { case id, t, s, x, p, st }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, uid()); t = c.v(.t, "task"); s = c.v(.s, String?.none)
        x = c.v(.x, ""); p = c.v(.p, Bool?.none); st = c.v(.st, Bool?.none)
    }

    var state: String { s ?? "open" }
    var isOpenTask: Bool { t == "task" && (state == "open" || state == "started") }
    var isClosed: Bool { ["done", "cancelled", "migrated"].contains(state) }
    var pri: Bool { p ?? false }

    /// 输入时的前缀：o 开头 = 事件，- 开头 = 备注，! 开头 = 重要
    static func parseNew(_ raw: String) -> Item {
        var it = Item(x: raw)
        if let m = raw.firstMatch(of: /^[oO○]\s+([\s\S]*)$/) { it.t = "event"; it.x = String(m.1) }
        else if let m = raw.firstMatch(of: /^[-–]\s+([\s\S]*)$/) { it.t = "note"; it.x = String(m.1) }
        if let m = it.x.firstMatch(of: /^[!！*★]\s*([\s\S]*)$/) { it.p = true; it.x = String(m.1) }
        return it
    }

    mutating func cycle() {
        if t == "note" { return }
        if t == "event" { s = state == "done" ? "open" : "done"; return }
        s = ["open": "started", "started": "done"][state] ?? "open"
    }
}

struct Card: Codable, Identifiable, Equatable {
    var id: String = uid()
    var title: String = ""
    var body: String = ""
    var tag: Bool = true

    init(id: String = uid(), title: String = "", body: String = "", tag: Bool = true) {
        self.id = id; self.title = title; self.body = body; self.tag = tag
    }
    enum CodingKeys: String, CodingKey { case id, title, body, tag }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, uid()); title = c.v(.title, ""); body = c.v(.body, ""); tag = c.v(.tag, false)
    }
}

struct Day: Codable, Equatable {
    var dot: String? = nil
    var mood: String? = nil
    var main: [Item] = []
    var light: [Item] = []
    var note: String = ""
    var mlog: String = ""
    var times: [String: String] = [:]
    var showTime: Bool = false
    var cards: [Card] = []

    init() {}
    enum CodingKeys: String, CodingKey { case dot, mood, main, light, note, mlog, times, showTime, cards }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dot = c.v(.dot, String?.none); mood = c.v(.mood, String?.none)
        main = c.v(.main, []); light = c.v(.light, [])
        note = c.v(.note, ""); mlog = c.v(.mlog, "")
        times = c.v(.times, [:]); showTime = c.v(.showTime, false); cards = c.v(.cards, [])
    }
    // 网页版 day() 会读 o.dot / o.mood，写 null 和不写都行；这里显式写 null，和网页导出的格式一样
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dot, forKey: .dot); try c.encode(mood, forKey: .mood)
        try c.encode(main, forKey: .main); try c.encode(light, forKey: .light)
        try c.encode(note, forKey: .note); try c.encode(mlog, forKey: .mlog)
        try c.encode(times, forKey: .times); try c.encode(showTime, forKey: .showTime)
        try c.encode(cards, forKey: .cards)
    }

    var isEmpty: Bool {
        dot == nil && mood == nil && main.isEmpty && light.isEmpty && note.isEmpty && mlog.isEmpty
            && cards.isEmpty && !times.values.contains { !$0.isEmpty }
    }
}

struct Habit: Codable, Identifiable, Equatable {
    var id: String = uid()
    var name: String = ""
    var marks: [String] = Array(repeating: "", count: 7)
    init(id: String = uid(), name: String = "") { self.id = id; self.name = name }
    enum CodingKeys: String, CodingKey { case id, name, marks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, uid()); name = c.v(.name, ""); marks = Week.seven(c.v(.marks, []))
    }
}

struct Score: Codable, Identifiable, Equatable {
    var id: String = uid()
    var name: String = ""
    var vals: [String] = Array(repeating: "", count: 7)
    init(id: String = uid(), name: String = "") { self.id = id; self.name = name }
    enum CodingKeys: String, CodingKey { case id, name, vals }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, uid()); name = c.v(.name, ""); vals = Week.seven(c.v(.vals, []))
    }
}

struct Sleep: Codable, Equatable {
    var bed: [String] = Array(repeating: "", count: 7)
    var wake: [String] = Array(repeating: "", count: 7)
    var wt: [String] = Array(repeating: "", count: 7)
    init() {}
    enum CodingKeys: String, CodingKey { case bed, wake, wt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bed = Week.seven(c.v(.bed, [])); wake = Week.seven(c.v(.wake, [])); wt = Week.seven(c.v(.wt, []))
    }
}

struct WList: Codable, Identifiable, Equatable {
    var id: String = uid()
    var title: String = ""
    var items: [Item] = []
    init(id: String = uid(), title: String = "", items: [Item] = []) { self.id = id; self.title = title; self.items = items }
    enum CodingKeys: String, CodingKey { case id, title, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, uid()); title = c.v(.title, ""); items = c.v(.items, [])
    }
}

struct Week: Codable, Equatable {
    var serious: [Item] = []
    var light: [Item] = []
    var track: [Item] = []
    var habits: [Habit] = []
    var scores: [Score] = []
    var sleep = Sleep()
    var lists: [WList] = []
    var thoughts: String = ""

    init() {}
    enum CodingKeys: String, CodingKey { case serious, light, track, habits, scores, sleep, lists, thoughts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serious = c.v(.serious, []); light = c.v(.light, []); track = c.v(.track, [])
        habits = c.v(.habits, []); scores = c.v(.scores, []); sleep = c.v(.sleep, Sleep())
        lists = c.v(.lists, []); thoughts = c.v(.thoughts, "")
    }

    static func seven(_ a: [String]) -> [String] {
        a.count >= 7 ? Array(a.prefix(7)) : a + Array(repeating: "", count: 7 - a.count)
    }
}

struct Month: Codable, Equatable {
    var goals: [Item] = []
    init() {}
    enum CodingKeys: String, CodingKey { case goals }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goals = c.v(.goals, [])
    }
}

struct Col: Codable, Identifiable, Equatable {
    var id: String = uid()
    var title: String = ""
    var items: [Item] = []
    init(id: String = uid(), title: String = "", items: [Item] = []) { self.id = id; self.title = title; self.items = items }
    enum CodingKeys: String, CodingKey { case id, title, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, uid()); title = c.v(.title, ""); items = c.v(.items, [])
    }
}

struct Settings: Codable, Equatable {
    var sym: String = "box"
    init() {}
    enum CodingKeys: String, CodingKey { case sym }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sym = c.v(.sym, "box")
    }
}

struct Doc: Codable, Equatable {
    var app = "mini-bujo"
    var v = 1
    /// 毫秒时间戳，和网页版一样用来判断哪份更新
    var updatedAt: Double = 0
    var settings = Settings()
    var moodLabels: [String: String] = Doc.defaultMoodLabels
    var days: [String: Day] = [:]
    var weeks: [String: Week] = [:]
    var months: [String: Month] = [:]
    var cols: [Col] = []

    static let defaultMoodLabels: [String: String] = [
        "red": "压力大 · stressful / angry",
        "orange": "低落 · sad / insecure",
        "yellow": "疲惫 · tired / uneventful",
        "green": "高效 · productive / positive",
        "blue": "放松 · chill / lazy",
    ]
    static let defaultHabits = ["shower 洗澡", "exercise 运动", "reading 阅读", "study 学习", "journal 日记"]
    static let defaultScores = ["productivity 效率", "energy 精力"]
    static let defaultLists = ["reading list", "watch list", "fun list", "deliveries 快递"]

    init() {}
    enum CodingKeys: String, CodingKey { case app, v, updatedAt, settings, moodLabels, days, weeks, months, cols }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.days) || c.contains(.weeks) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not a mini bujo file"))
        }
        app = c.v(.app, "mini-bujo"); v = c.v(.v, 1); updatedAt = c.v(.updatedAt, 0)
        settings = c.v(.settings, Settings())
        moodLabels = Doc.defaultMoodLabels.merging(c.v(.moodLabels, [:])) { _, new in new }
        days = c.v(.days, [:]); weeks = c.v(.weeks, [:]); months = c.v(.months, [:]); cols = c.v(.cols, [])
    }

    static func parse(_ data: Data) -> Doc? { try? JSONDecoder().decode(Doc.self, from: data) }

    /// 和网页版 serialize() 一样：空白的日子不写进文件
    func serialized() -> Data {
        var d = self
        d.days = days.filter { !$0.value.isEmpty }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(d)) ?? Data()
    }

    func moodLabel(_ m: Mood) -> String { moodLabels[m.rawValue] ?? "" }

    /// 新的一周：沿用上一周的习惯、打分项和清单（清单只带未完成的条目）
    func newWeek(_ mon: String) -> Week {
        let prevKey = weeks.keys.filter { $0 < mon && !(weeks[$0]?.habits.isEmpty ?? true) }.max()
        let p = prevKey.flatMap { weeks[$0] }
        var w = Week()
        w.habits = (p?.habits.map(\.name) ?? Doc.defaultHabits).map { Habit(name: $0) }
        w.scores = (p?.scores.map(\.name) ?? Doc.defaultScores).map { Score(name: $0) }
        w.lists = p.map { p in
            p.lists.map { l in WList(title: l.title, items: l.items.filter { !$0.isClosed }.map { var i = $0; i.id = uid(); return i }) }
        } ?? Doc.defaultLists.map { WList(title: $0) }
        return w
    }
}
