import XCTest
@testable import MiniBujo

final class ModelTests: XCTestCase {
    /// 网页版导出的 JSON（节选，字段缺失 / 多余都有）
    let webJSON = """
    {
     "app": "mini-bujo", "v": 1, "updatedAt": 1762841520000,
     "settings": { "sym": "dot" },
     "moodLabels": { "red": "很烦" },
     "days": {
      "2026-11-10": { "dot": "red", "mood": "green", "main": [ { "id": "a1", "t": "task", "s": "started", "x": "写报告", "p": true } ],
                      "light": [], "note": "", "mlog": "15:30 牙医", "times": { "09": "开会" }, "showTime": true, "cards": [] },
      "2026-11-11": { "dot": null, "main": [ { "id": "b1", "t": "event", "s": "open", "x": "生日" } ] }
     },
     "weeks": {
      "2026-11-09": { "serious": [], "light": [], "track": [],
        "habits": [ { "id": "h1", "name": "运动", "marks": ["X", "", "/"] } ],
        "scores": [], "sleep": { "bed": ["23:30"], "wake": ["07:15"], "wt": [""] },
        "lists": [ { "id": "l1", "title": "reading list", "items": [ { "id": "i1", "t": "task", "s": "done", "x": "书 A" }, { "id": "i2", "t": "task", "s": "open", "x": "书 B" } ] } ],
        "thoughts": "" }
     },
     "months": { "2026-11": { "goals": [] } },
     "cols": [ { "id": "c1", "title": "open emails", "items": [] } ],
     "futureField": 42
    }
    """

    func testDecodesWebExport() throws {
        let d = try XCTUnwrap(Doc.parse(Data(webJSON.utf8)))
        XCTAssertEqual(d.settings.sym, "dot")
        XCTAssertEqual(d.moodLabels["red"], "很烦")
        XCTAssertEqual(d.moodLabels["blue"], Doc.defaultMoodLabels["blue"], "缺的心情标签用默认值")
        XCTAssertEqual(d.days["2026-11-10"]?.main.first?.pri, true)
        XCTAssertEqual(d.days["2026-11-11"]?.times, [:], "缺的字段补齐")
        XCTAssertEqual(d.weeks["2026-11-09"]?.habits.first?.marks.count, 7, "不足 7 天的数组补齐")
        XCTAssertEqual(d.weeks["2026-11-09"]?.sleep.bed[0], "23:30")
        XCTAssertEqual(d.weeks["2026-11-09"]?.sleep.rhr, Array(repeating: "", count: 7), "旧数据缺少静息心率时补空白")
    }

    func testRestingHeartRateWebRoundTrip() throws {
        let json = #"{"weeks":{"2026-11-09":{"sleep":{"wt":["52.4"],"rhr":["62","","58"]}}}}"#
        let doc = try XCTUnwrap(Doc.parse(Data(json.utf8)))
        let sleep = try XCTUnwrap(doc.weeks["2026-11-09"]?.sleep)
        XCTAssertEqual(sleep.rhr, ["62", "", "58", "", "", "", ""])
        XCTAssertEqual(sleep.wt[0], "52.4")
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: doc.serialized()) as? [String: Any])
        let weeks = try XCTUnwrap(output["weeks"] as? [String: [String: Any]])
        let exported = try XCTUnwrap(weeks["2026-11-09"]?["sleep"] as? [String: Any])
        XCTAssertEqual(exported["rhr"] as? [String], sleep.rhr)
        XCTAssertEqual(Doc.parse(doc.serialized())?.weeks["2026-11-09"]?.sleep, sleep)
        XCTAssertTrue(doc.newWeek("2026-11-16").sleep.rhr.allSatisfy(\.isEmpty), "新周不沿用测量值")
    }

    func testRestingHeartRateChartData() {
        let model = RestingHeartRateModel(["62", "", "58", "0", "-1", "60.5", "NaN"])
        XCTAssertEqual(model.values, [62, nil, 58, nil, nil, nil, nil])
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(RestingHeartRateModel([]).isEmpty)
        for raw in [["60"], Array(repeating: "60", count: 7), ["1", "999"]] {
            let chart = RestingHeartRateModel(raw)
            XCTAssertGreaterThan(chart.upper, chart.lower)
            for value in chart.values.compactMap({ $0 }) {
                XCTAssertGreaterThanOrEqual(value, chart.lower)
                XCTAssertLessThanOrEqual(value, chart.upper)
            }
        }
    }

    func testRejectsForeignJSON() {
        XCTAssertNil(Doc.parse(Data(#"{"hello": 1}"#.utf8)))
        XCTAssertNil(Doc.parse(Data("not json".utf8)))
    }

    func testRoundTripKeepsWebShape() throws {
        var d = try XCTUnwrap(Doc.parse(Data(webJSON.utf8)))
        d.days["2026-12-01"] = Day()   // 空的日子不应写进文件
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: d.serialized()) as? [String: Any])
        let days = try XCTUnwrap(obj["days"] as? [String: Any])
        XCTAssertNil(days["2026-12-01"])
        let day = try XCTUnwrap(days["2026-11-11"] as? [String: Any])
        // 网页版 bindSet 会直接写 o.times[...]、o.cards.push(...)，这些字段必须存在
        for k in ["main", "light", "note", "mlog", "times", "showTime", "cards"] { XCTAssertNotNil(day[k], k) }
        XCTAssertEqual(obj["app"] as? String, "mini-bujo")
        XCTAssertEqual(Doc.parse(d.serialized())?.days["2026-11-10"], d.days["2026-11-10"])
    }

    func testParseNewPrefixes() {
        XCTAssertEqual(Item.parseNew("o 生日").t, "event")
        XCTAssertEqual(Item.parseNew("- 想法").t, "note")
        let p = Item.parseNew("！交房租")
        XCTAssertEqual(p.t, "task"); XCTAssertEqual(p.p, true); XCTAssertEqual(p.x, "交房租")
        let ep = Item.parseNew("o !面试")
        XCTAssertEqual(ep.t, "event"); XCTAssertEqual(ep.p, true); XCTAssertEqual(ep.x, "面试")
    }

    func testCycle() {
        var t = Item(); t.cycle(); XCTAssertEqual(t.s, "started"); t.cycle(); XCTAssertEqual(t.s, "done"); t.cycle(); XCTAssertEqual(t.s, "open")
        var e = Item(t: "event"); e.cycle(); XCTAssertEqual(e.s, "done"); e.cycle(); XCTAssertEqual(e.s, "open")
        var n = Item(t: "note"); n.cycle(); XCTAssertEqual(n.s, "open")
    }

    func testDates() {
        XCTAssertEqual(Dates.wdIdx("2026-11-09"), 0)   // 周一
        XCTAssertEqual(Dates.wdIdx("2026-11-15"), 6)   // 周日
        XCTAssertEqual(Dates.mondayOf("2026-11-15"), "2026-11-09")
        XCTAssertEqual(Dates.weekNo("2026-11-11"), 46)
        XCTAssertEqual(Dates.weekNo("2027-01-01"), 53)
        XCTAssertEqual(Dates.addMonths("2026-01-31", 1), "2026-02-01")
        XCTAssertEqual(Dates.daysInMonth(2028, 2), 29)
    }

    func testNewWeekCarriesOverOpenListItems() throws {
        let d = try XCTUnwrap(Doc.parse(Data(webJSON.utf8)))
        let w = d.newWeek("2026-11-16")
        XCTAssertEqual(w.habits.map(\.name), ["运动"])
        XCTAssertEqual(w.lists.first?.items.map(\.x), ["书 B"])
        XCTAssertNotEqual(w.lists.first?.items.first?.id, "i2", "带过去的条目换新 id")
    }

    @MainActor
    func testMigrateAndPeek() throws {
        let store = BujoStore(doc: try XCTUnwrap(Doc.parse(Data(webJSON.utf8))))
        _ = store.peekWeek("2026-11-23")
        XCTAssertNil(store.doc.weeks["2026-11-23"], "只是翻看不落盘")
        store.migrateAll([.day("2026-11-10", "main")])
        XCTAssertEqual(store.doc.days["2026-11-10"]?.main.first?.s, "migrated")
        XCTAssertEqual(store.doc.days["2026-11-11"]?.main.last?.x, "写报告")
        XCTAssertEqual(store.doc.days["2026-11-11"]?.main.last?.s, "open")
        store.addItem(.wk("2026-11-23", "serious"), "o 交作业")
        XCTAssertEqual(store.doc.weeks["2026-11-23"]?.serious.first?.t, "event")
        XCTAssertEqual(store.doc.weeks["2026-11-23"]?.habits.map(\.name), ["运动"])
    }
}

final class ReminderTests: XCTestCase {
    func date(_ s: String, _ h: Int, _ m: Int = 0) -> Date { ReminderPlanner.at(s, minutes: h * 60 + m) }

    func testFindsTimesInText() {
        XCTAssertEqual(ReminderPlanner.times(in: "15:30 牙医，21：05 电话"), [15 * 60 + 30, 21 * 60 + 5])
        XCTAssertEqual(ReminderPlanner.times(in: "比分 3:2:1 / 版本 1.2 / 125:30"), [])
        XCTAssertEqual(ReminderPlanner.times(in: "9:00"), [540])
    }

    func testPlan() {
        var d = Doc()
        var day = Day()
        day.dot = "red"; day.mlog = "15:30 牙医"; day.times = ["09": "开会"]
        day.main = [Item(x: "交报告"), Item(t: "note", x: "- 10:00 只是备注")]
        d.days["2026-11-12"] = day
        var prefs = ReminderPrefs()
        prefs.checkin = false; prefs.weekly = false
        let plan = ReminderPlanner.plan(doc: d, prefs: prefs, now: date("2026-11-11", 12))
        let byID = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0) })
        XCTAssertEqual(byID["bujo.eve.2026-11-12"]?.fire, date("2026-11-11", 21))
        XCTAssertEqual(byID["bujo.morning.2026-11-12"]?.fire, date("2026-11-12", 8))
        XCTAssertEqual(byID["bujo.morning.2026-11-12"]?.body, "15:30 牙医")
        XCTAssertEqual(byID["bujo.tl.2026-11-12.09"]?.fire, date("2026-11-12", 8, 50))
        XCTAssertTrue(plan.contains { $0.title == "15:30 牙医" && $0.fire == date("2026-11-12", 15, 20) })
        XCTAssertFalse(plan.contains { $0.title.contains("只是备注") }, "备注不提醒")
        XCTAssertEqual(plan.map(\.fire), plan.map(\.fire).sorted())
    }

    func testPastAndDisabled() {
        var d = Doc()
        var day = Day(); day.times = ["08": "早会"]
        d.days["2026-11-11"] = day
        var prefs = ReminderPrefs(); prefs.checkin = false; prefs.weekly = false
        XCTAssertTrue(ReminderPlanner.plan(doc: d, prefs: prefs, now: date("2026-11-11", 12)).isEmpty, "过去的时间不排")
        prefs.enabled = false
        XCTAssertTrue(ReminderPlanner.plan(doc: d, prefs: prefs, now: date("2026-11-10", 12)).isEmpty)
    }

    func testCheckinSkipsWhenTodayIsDone() {
        var d = Doc()
        var w = Week(); var h = Habit(name: "运动"); h.marks[2] = "X"; w.habits = [h]
        d.weeks["2026-11-09"] = w
        var day = Day(); day.mood = "green"
        d.days["2026-11-11"] = day
        var prefs = ReminderPrefs(); prefs.dotDays = false; prefs.weekly = false
        let plan = ReminderPlanner.plan(doc: d, prefs: prefs, now: date("2026-11-11", 12))
        XCTAssertNil(plan.first { $0.id == "bujo.checkin.2026-11-11" })
        XCTAssertNotNil(plan.first { $0.id == "bujo.checkin.2026-11-12" })

        d.days["2026-11-11"]?.mood = nil
        let plan2 = ReminderPlanner.plan(doc: d, prefs: prefs, now: date("2026-11-11", 12))
        XCTAssertEqual(plan2.first { $0.id == "bujo.checkin.2026-11-11" }?.body, "心情还没记")
    }

    func testCapsAt60() {
        var d = Doc()
        for k in 0..<14 {
            var day = Day()
            day.times = Dictionary(uniqueKeysWithValues: (6..<24).map { (Dates.pad($0), "事 \($0)") })
            d.days[Dates.addDays("2026-11-12", k)] = day
        }
        let plan = ReminderPlanner.plan(doc: d, prefs: ReminderPrefs(), now: date("2026-11-11", 12))
        XCTAssertEqual(plan.count, ReminderPlanner.maxCount)
    }
}
