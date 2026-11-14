import SwiftUI

struct MonthLeft: View {
    @Environment(BujoStore.self) private var store

    var body: some View {
        let key = String(store.date.prefix(7)), y = Dates.year(store.date), m = Dates.month(store.date)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(Dates.MONTHS[m - 1], sub: "\(y) · 月视图", size: 46)
            Calendar(key: key, y: y, m: m)
            Hint("点日期贴圆点：\(Text("●").foregroundStyle(C.red)) 重要安排  \(Text("●").foregroundStyle(C.blue)) 一般预约 · 再点一次撕掉 · 长按可打开那一天")
            SectionTitle("本月目标 · goals")
            BulletList(ref: .mg(key), placeholder: "这个月想做成的事…")
        }
    }
}

private struct Calendar: View {
    @Environment(BujoStore.self) private var store
    let key: String, y: Int, m: Int

    var body: some View {
        let n = Dates.daysInMonth(y, m), lead = Dates.wdIdx("\(key)-01"), t = Dates.today()
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(spacing: 4) {
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(Dates.WD, id: \.self) { Text($0).font(.hand(18)).foregroundStyle(C.ink2) }
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...n, id: \.self) { d in
                    let s = "\(key)-\(Dates.pad(d))", o = store.doc.days[s]
                    cell(d: d, s: s, dot: o?.dot, today: s == t, has: !(o?.main.isEmpty ?? true) || !(o?.light.isEmpty ?? true))
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.ink, lineWidth: 1.8))
    }

    private func cell(d: Int, s: String, dot: String?, today: Bool, has: Bool) -> some View {
        let fill = C.dot(dot)
        return Button { store.cycleDot(s) } label: {
            ZStack {
                Circle().fill(fill ?? .clear)
                Text("\(d)").font(.hand(20)).foregroundStyle(fill == nil ? C.ink : .white)
                if has {
                    Circle().fill(fill == nil ? C.ink : .white).opacity(0.6).frame(width: 4, height: 4).offset(y: 12)
                }
                if today { Circle().stroke(C.ink, lineWidth: 1.8) }
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("打开这一天") { store.go(.day, s) }
        }
        .help("点一下贴圆点：红 → 蓝 → 无")
    }
}

struct MonthRight: View {
    @Environment(BujoStore.self) private var store

    var body: some View {
        let key = String(store.date.prefix(7)), n = Dates.daysInMonth(Dates.year(store.date), Dates.month(store.date))
        let t = Dates.today()
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("monthly log", sub: "每天一行，写上事情和时间 · 点日期进入日视图")
            VStack(spacing: 0) {
                ForEach(1...n, id: \.self) { d in
                    logRow(d: d, s: "\(key)-\(Dates.pad(d))", today: t)
                }
            }
        }
    }

    private func logRow(d: Int, s: String, today: String) -> some View {
        let o = store.doc.days[s], i = Dates.wdIdx(s), fill = C.dot(o?.dot)
        return HStack(alignment: .top, spacing: 8) {
            Button { store.go(.day, s) } label: {
                Text("\(d)").font(.hand(18)).foregroundStyle(fill == nil ? C.ink : .white)
                    .frame(width: 26, height: 22)
                    .background(Capsule().fill(fill ?? .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .help("打开这一天")
            Text(Dates.WD[i]).font(.hand(17)).foregroundStyle(s == today ? C.ink : C.ink3)
                .frame(width: 34, height: 26, alignment: .leading)
            TextField("", text: Binding(get: { store.doc.days[s]?.mlog ?? "" },
                                        set: { v in store.editDay(s) { $0.mlog = v } }), axis: .vertical)
                .textFieldStyle(.plain).font(.ui(14)).foregroundStyle(C.ink)
                .padding(.vertical, 3)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(C.line.opacity(0.6)).frame(height: 1) }
        .overlay(alignment: .top) { if i == 0 { Rectangle().fill(C.line).frame(height: 1.5) } }
    }
}
