import Foundation

/// 日期一律用 "YYYY-MM-DD" 字符串（本地时区），和网页版的 JSON 键保持一致。
enum Dates {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    static func ds(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(pad(c.month!))-\(pad(c.day!))"
    }

    static func pd(_ s: String) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 0)) ?? Date()
    }

    static func addDays(_ s: String, _ n: Int) -> String {
        ds(cal.date(byAdding: .day, value: n, to: pd(s)) ?? pd(s))
    }

    static func addMonths(_ s: String, _ n: Int) -> String {
        let first = pd(String(s.prefix(7)) + "-01")
        return ds(cal.date(byAdding: .month, value: n, to: first) ?? first)
    }

    static func today() -> String { ds(Date()) }

    /// 周一 = 0 … 周日 = 6
    static func wdIdx(_ s: String) -> Int { (cal.component(.weekday, from: pd(s)) + 5) % 7 }

    static func mondayOf(_ s: String) -> String { addDays(s, -wdIdx(s)) }

    static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        let d = cal.date(from: DateComponents(year: y, month: m, day: 1))!
        return cal.range(of: .day, in: .month, for: d)!.count
    }

    static func year(_ s: String) -> Int { Int(s.prefix(4)) ?? 2000 }
    static func month(_ s: String) -> Int { Int(s.dropFirst(5).prefix(2)) ?? 1 }
    static func dayOfMonth(_ s: String) -> Int { Int(s.dropFirst(8).prefix(2)) ?? 1 }

    static func fmtMD(_ s: String) -> String { "\(month(s))/\(dayOfMonth(s))" }

    /// ISO 周数，和网页版 weekNo() 一致
    static func weekNo(_ s: String) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        return iso.component(.weekOfYear, from: pd(s))
    }

    static func hhmm(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return "\(pad(c.hour!)):\(pad(c.minute!))"
    }

    static let WD = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let WD_CN = ["一", "二", "三", "四", "五", "六", "日"]
    static let WD_FULL = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let MONTHS = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]
}
